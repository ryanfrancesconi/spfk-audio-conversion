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
/// The entire source file is loaded into memory as a PCM buffer, the edit is applied
/// (trim → reverse → fade), and the result is written to the output URL. Text metadata
/// and markers are copied from the source to the output after writing.
///
/// PCM formats (WAV, AIFF, CAF) and AAC (M4A) are written directly via `AVAudioFile`.
/// Formats unsupported by `AVAudioFile` (MP3, FLAC, OGG) are written via an intermediate
/// WAV file passed through ``AudioFormatConverter``.
///
/// - Note: The entire file is loaded into memory. Suitable for sample libraries and
///   short clips. Very long recordings may exhaust available RAM.
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

    public init(
        sourceURL: URL,
        audioTrack: AudioTrackDescription.ID? = nil,
        edit: AudioEditDescription,
        outputURL: URL,
        fileConflictScheme: FileConflictScheme = .error,
        metadataCopyScheme: MetadataCopyScheme = .copyAll
    ) {
        self.sourceURL = sourceURL
        self.audioTrack = audioTrack
        self.edit = edit
        self.outputURL = outputURL
        self.fileConflictScheme = fileConflictScheme
        self.metadataCopyScheme = metadataCopyScheme
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
            let processed = try readAndApplyEdit(from: decoder)
            return try await finish(processed, fileFormat: decoder.processingFormat, to: resolvedOutput)
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
            let processed = try readAndApplyEdit(from: reader)
            return try await finish(processed, fileFormat: try await fileFormat(of: reader), to: resolvedOutput)
        }

        let audioFile = try AVAudioFile(forReading: sourceURL)

        // AVAudioFile.length returns 0 for some compressed formats (e.g. MP3) because
        // MPEG audio doesn't store a reliable frame count. Fall back to the asset duration.
        let frameCapacity: AVAudioFrameCount
        if audioFile.length > 0 {
            frameCapacity = try .checked(audioFile.length, for: sourceURL)
        } else {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            frameCapacity = try .checked(
                roundingUp: duration.seconds * audioFile.processingFormat.sampleRate,
                for: sourceURL
            )
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let safeEdit = edit.clampingFadesToTrim(fileDuration: Double(frameCapacity) / sampleRate)

        // Read only the trim window. A 2 second trim out of an hour otherwise allocates the hour:
        // measured 1325 MB for 1.9 MB of output, and `SegmentDivider` runs four of these at once.
        //
        // A file that cannot state its own length cannot be seeked by frame either, so it is read
        // whole as before and trimmed in memory.
        let window = audioFile.length > 0
            ? Self.window(for: safeEdit.trim, totalFrames: frameCapacity, sampleRate: sampleRate)
            : (offset: AVAudioFrameCount(0), frameCount: frameCapacity)

        let isPreTrimmed = window.offset > 0 || window.frameCount < frameCapacity

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: window.frameCount
        ) else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        if window.offset > 0 {
            audioFile.framePosition = AVAudioFramePosition(window.offset)
        }

        try audioFile.read(into: buffer, frameCount: window.frameCount)

        guard buffer.frameLength > 0 else {
            throw NSError(description: "Read 0 frames from \(sourceURL.lastPathComponent)")
        }

        let processed = try buffer.applying(safeEdit, isPreTrimmed: isPreTrimmed)

        return try await finish(processed, fileFormat: audioFile.fileFormat, to: resolvedOutput)
    }

    // MARK: - Private

    /// Writes the edited buffer and carries the source's metadata onto it.
    ///
    /// Shared by both read paths, which differ only in what they decode through.
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
                settings: Self.resolveOutputSettings(fileFormat: fileFormat, buffer: buffer, outputURL: url),
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
    private static func resolveOutputSettings(
        fileFormat: AVAudioFormat,
        buffer: AVAudioPCMBuffer,
        outputURL: URL
    ) -> [String: Any] {
        let outputType = AudioFileType(pathExtension: outputURL.pathExtension)
        let sourceFormatID = fileFormat.settings[AVFormatIDKey] as? UInt32 ?? kAudioFormatLinearPCM

        if outputType?.isPCM == true, sourceFormatID != kAudioFormatLinearPCM {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: Int(buffer.format.channelCount),
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
            ]
        }
        return fileFormat.settings
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
