// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMatroska
import SPFKMetadata
import SPFKVideo

/// Applies an ``AudioEditDescription`` to an audio file and writes the result to an output URL.
///
/// The trim window is read as a PCM buffer (a file that cannot state its length is read whole),
/// the edit is applied (see ``processEdit(_:)``), and the result is written to the output URL. Text metadata
/// and markers are copied from the source to the output after writing.
///
/// PCM formats (WAV, AIFF, CAF) and AAC (M4A) are written directly via `AVAudioFile`.
/// Formats unsupported by `AVAudioFile` (MP3, FLAC, OGG) are written via an intermediate
/// WAV file passed through ``AudioFormatConverter``.
public actor AudioEditRenderer {
    /// The source audio file to read.
    public let sourceURL: URL

    /// The audio track to render, or `nil` for the container's first. An identifier the file does
    /// not carry falls back to the first.
    public let audioTrack: AudioTrackDescription.ID?

    /// The edit operations to apply.
    public let edit: AudioEditDescription

    /// The destination URL for the rendered output.
    public let outputURL: URL

    /// Determines how to handle an existing file at ``outputURL``. Defaults to `.error`.
    public var fileConflictScheme: FileConflictScheme

    /// Controls which metadata categories are copied from source to output. Defaults to `.copyAll`.
    public var metadataCopyScheme: MetadataCopyScheme

    /// App-wide render choices, such as how a channel edit that would clip is brought under 0 dBFS.
    public let renderSettings: AudioRenderSettings

    /// Folds a 2-channel render to one channel after the edit's own channel operation, for a
    /// destination that takes mono. A render the edit already made mono is left as it is.
    public let conformToMono: MonoSource?

    public init(
        sourceURL: URL,
        audioTrack: AudioTrackDescription.ID? = nil,
        edit: AudioEditDescription,
        outputURL: URL,
        fileConflictScheme: FileConflictScheme = .error,
        metadataCopyScheme: MetadataCopyScheme = .copyAll,
        renderSettings: AudioRenderSettings = AudioRenderSettings(),
        conformToMono: MonoSource? = nil
    ) {
        self.sourceURL = sourceURL
        self.audioTrack = audioTrack
        self.edit = edit
        self.outputURL = outputURL
        self.fileConflictScheme = fileConflictScheme
        self.metadataCopyScheme = metadataCopyScheme
        self.renderSettings = renderSettings
        self.conformToMono = conformToMono
    }

    /// Applies the edit and writes the processed audio to the output URL.
    ///
    /// - Returns: The URL of the written file. When ``fileConflictScheme`` is `.unique`
    ///   this may differ from ``outputURL``.
    /// - Throws: If the source cannot be read, the edit cannot be applied, or writing fails.
    @discardableResult
    public func render() async throws -> URL {
        try Task.checkCancellation()

        let resolvedOutput = try resolveConflict()

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        // Matroska is opaque to AVAudioFile, which throws `'fmt?'` on one. It decodes through the
        // same reader the conversion path uses.
        if AudioFileType(pathExtension: sourceURL.pathExtension)?.isMatroska == true {
            let decoder = try MatroskaAudioDecoder(url: sourceURL, audioTrack: audioTrack)
            let fileFormat = decoder.processingFormat
            let processed = try processEdit(readWindow(from: decoder), fileFormat: fileFormat, writingTo: resolvedOutput)
            return try await finish(processed, fileFormat: fileFormat, to: resolvedOutput)
        }

        // MXF decodes fine through `AVAssetReaderPCMSource`, but **nothing here can write one**:
        // the render replaces the source in place, so the output carries the source's extension,
        // and no writer in this app or in AVFoundation produces MXF. Refused with a reason rather
        // than left to `AVAudioFile`, which throws a bare `'fmt?'` the user sees as a failed save
        // with no cause.
        if AudioFileType(pathExtension: sourceURL.pathExtension) == .mxf {
            throw NSError(
                description: "Audio edits cannot be rendered into \(sourceURL.lastPathComponent): MXF cannot be written"
            )
        }

        // `AVAudioFile` reads the first audio track and cannot be pointed at another.
        if let reader = try await selectedTrackReader() {
            let fileFormat = try await fileFormat(of: reader)
            let processed = try processEdit(readWindow(from: reader), fileFormat: fileFormat, writingTo: resolvedOutput)
            return try await finish(processed, fileFormat: fileFormat, to: resolvedOutput)
        }

        let audioFile = try AVAudioFile(forReading: sourceURL)
        let processed = try processEdit(await readWindow(from: audioFile), fileFormat: audioFile.fileFormat, writingTo: resolvedOutput)
        return try await finish(processed, fileFormat: audioFile.fileFormat, to: resolvedOutput)
    }

    // MARK: - Private

    /// Writes the edited buffer and carries the source's metadata onto it.
    ///
    /// Shared by every read route, which differ only in what they decode through.
    private func finish(
        _ processed: AVAudioPCMBuffer,
        fileFormat: AVAudioFormat,
        to resolvedOutput: URL
    ) async throws -> URL {
        guard processed.frameLength > 0 else {
            throw NSError(description: "Edit produced 0 frames from \(sourceURL.lastPathComponent) — trim range may be outside file bounds")
        }

        try await write(processed, fileFormat: fileFormat, to: resolvedOutput)
        try await carryMetadata(to: resolvedOutput)
        try rewriteTrackList(of: resolvedOutput, for: renderedChannelOperations)

        // Re-write markers adjusted for the trim range, overwriting the unadjusted markers
        // that copyMetadata wrote above.
        if metadataCopyScheme.includesMarkers, edit.trim.inPoint > 0 || edit.trim.outPoint > 0 {
            let renderedDuration = Double(processed.frameLength) / processed.format.sampleRate

            guard await adjustAndWriteMarkers(to: resolvedOutput, newDuration: renderedDuration) else {
                try? FileManager.default.removeItem(at: resolvedOutput)
                throw NSError(description: "The markers of \(sourceURL.lastPathComponent) could not be written to the render")
            }
        }

        return resolvedOutput
    }

    /// Frames per decoder read while filling the window.
    static let decodeChunkFrames: AVAudioFrameCount = 16384

    /// The frames a trim covers, in the same rounding `AVAudioPCMBuffer.extract(from:to:)` uses —
    /// the two have to agree, since either can produce the rendered buffer.
    static func window(
        for trim: TrimDescription,
        totalFrames: AVAudioFrameCount,
        sampleRate: Double
    ) -> (offset: AVAudioFrameCount, frameCount: AVAudioFrameCount) {
        guard !trim.isEmpty else { return (0, totalFrames) }

        let start = min(AVAudioFrameCount(max(0, trim.inPoint * sampleRate)), totalFrames)

        var end = totalFrames

        if trim.outPoint > 0 {
            end = min(AVAudioFrameCount(trim.outPoint * sampleRate), totalFrames)

            if end == 0 { end = totalFrames }
        }

        // An empty or inverted window is left to the edit itself to reject, which it does with a
        // message naming the trim rather than the read.
        guard end > start else { return (0, totalFrames) }

        return (start, end - start)
    }

    private func resolveConflict() throws -> URL {
        guard outputURL.exists else { return outputURL }

        switch fileConflictScheme {
        case .overwrite:
            try FileManager.default.removeItem(at: outputURL)
            return outputURL
        case .unique:
            return FileSystem.nextAvailableURL(outputURL)
        case .error:
            throw NSError(description: "Output file already exists at \(outputURL.path)")
        }
    }

    /// Writes the processed PCM buffer to `url`, preserving the source file format.
    ///
    /// PCM and AAC formats are written directly via `AVAudioFile`. Formats unsupported by
    /// `AVAudioFile` (MP3, FLAC, OGG) go through an intermediate float WAV.
    private func write(
        _ buffer: AVAudioPCMBuffer,
        fileFormat: AVAudioFormat,
        to url: URL
    ) async throws {
        if Self.isDirectlyWritable(url: url) {
            let outputFile = try AVAudioFile(
                forWriting: url,
                settings: Self.resolveOutputSettings(fileFormat: fileFormat, buffer: buffer.format, outputURL: url),
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: buffer)
        } else {
            try await writeViaIntermediateWAV(
                buffer,
                sampleRate: fileFormat.sampleRate,
                options: try await encodingOptions(matching: fileFormat, of: url),
                to: url
            )
        }
    }

    /// Resolves the AVAudioFile write settings for the given output URL.
    ///
    /// When the output is a PCM container (WAV/AIFF/CAF) but the source is compressed
    /// (e.g. MP4/AAC), the source `fileFormat.settings` contain codec parameters that
    /// AVAudioFile rejects with `kAudioFormatUnsupportedDataFormatError`. In that case,
    /// derive float32 PCM settings from the already-decompressed buffer instead.
    ///
    /// A channel edit can change the channel count, which the source's settings would otherwise
    /// write; a source channel layout is dropped with it, since it cannot describe the new count.
    static func resolveOutputSettings(
        fileFormat: AVAudioFormat,
        buffer: AVAudioFormat,
        outputURL: URL
    ) -> [String: Any] {
        let outputType = AudioFileType(pathExtension: outputURL.pathExtension)
        let sourceFormatID = fileFormat.settings[AVFormatIDKey] as? UInt32 ?? kAudioFormatLinearPCM

        if outputType?.isPCM == true, sourceFormatID != kAudioFormatLinearPCM {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: buffer.sampleRate,
                AVNumberOfChannelsKey: Int(buffer.channelCount),
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
            ]
        }

        var settings = fileFormat.settings

        if buffer.channelCount != fileFormat.channelCount {
            settings[AVNumberOfChannelsKey] = Int(buffer.channelCount)
            settings[AVChannelLayoutKey] = nil
        }

        return settings
    }

    /// True when the render is written as float PCM, which carries a peak above 0 dBFS intact.
    static func writesFloatPCM(fileFormat: AVAudioFormat, buffer: AVAudioFormat, outputURL: URL) -> Bool {
        guard isDirectlyWritable(url: outputURL) else { return false }

        let settings = resolveOutputSettings(fileFormat: fileFormat, buffer: buffer, outputURL: outputURL)

        return settings[AVFormatIDKey] as? UInt32 == kAudioFormatLinearPCM
            && settings[AVLinearPCMIsFloatKey] as? Bool == true
    }

    /// The source's own bit depth and bit rate, so a render written back in place re-encodes at
    /// what the file already was rather than at the converter's defaults.
    ///
    /// The intermediate is float, which would otherwise decide the depth of a FLAC.
    private func encodingOptions(matching fileFormat: AVAudioFormat, of url: URL) async throws -> AudioFormatConverterOptions {
        var options = AudioFormatConverterOptions()

        switch AudioFileType(pathExtension: url.pathExtension) {
        case .flac:
            let depth = fileFormat.streamDescription.pointee.sourceBitsPerChannel

            if let depth, depth == 16 || depth == 24 {
                options.bitsPerChannel = UInt32(depth)
            }

        case .mp3:
            // LAME takes a CBR rate, so a VBR source's average is snapped to one it accepts.
            let kbps = try await AVAudioFile(forReading: sourceURL).estimatedDataRate()

            if kbps > 0, let nearest = AudioFormatConverterOptions.supportedBitRates.min(by: {
                abs(Float($0) - kbps * 1000) < abs(Float($1) - kbps * 1000)
            }) {
                options.bitRate = nearest
            }

        default:
            break
        }

        return options
    }

    private func writeViaIntermediateWAV(
        _ buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        options: AudioFormatConverterOptions,
        to url: URL
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Scope tempFile so AVAudioFile is deallocated (and the WAV RIFF header finalized)
        // before the converter opens the file. Without this, libsndfile reads the RIFF
        // data-chunk size as 0 because AVAudioFile only writes it on close.
        do {
            let wavSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: Int(buffer.format.channelCount),
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
            ]

            let tempFile = try AVAudioFile(
                forWriting: tempURL,
                settings: wavSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try tempFile.write(from: buffer)
        }

        let convSource = AudioFormatConverterSource(
            input: tempURL,
            output: url,
            options: options,
            metadataCopyScheme: .ignore
        )

        try await AudioFormatConverter(source: convSource).start()
    }

    private static func isDirectlyWritable(url: URL) -> Bool {
        AudioFileType(pathExtension: url.pathExtension)?.isAVAudioFileWritable ?? true
    }
}
