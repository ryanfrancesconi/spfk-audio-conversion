// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata

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
        edit: AudioEditDescription,
        outputURL: URL,
        fileConflictScheme: FileConflictScheme = .error,
        metadataCopyScheme: MetadataCopyScheme = .copyAll
    ) {
        self.sourceURL = sourceURL
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

        let audioFile = try AVAudioFile(forReading: sourceURL)

        // AVAudioFile.length returns 0 for some compressed formats (e.g. MP3) because
        // MPEG audio doesn't store a reliable frame count. Fall back to the asset duration.
        let frameCapacity: AVAudioFrameCount
        if audioFile.length > 0 {
            frameCapacity = AVAudioFrameCount(audioFile.length)
        } else {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            frameCapacity = AVAudioFrameCount(ceil(duration.seconds * audioFile.processingFormat.sampleRate))
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCapacity
        ) else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        try audioFile.read(into: buffer)

        guard buffer.frameLength > 0 else {
            throw NSError(description: "Read 0 frames from \(sourceURL.lastPathComponent)")
        }

        let fileDuration = Double(buffer.frameLength) / audioFile.processingFormat.sampleRate
        let safeEdit = edit.clampingFadesToTrim(fileDuration: fileDuration)
        let processed = try buffer.applying(safeEdit)

        guard processed.frameLength > 0 else {
            throw NSError(description: "Edit produced 0 frames from \(sourceURL.lastPathComponent) — trim range may be outside file bounds")
        }

        try await write(processed, fileFormat: audioFile.fileFormat, to: resolvedOutput) // error here for large mp4

        let convSource = AudioFormatConverterSource(
            input: sourceURL,
            output: resolvedOutput,
            options: AudioFormatConverterOptions(),
            metadataCopyScheme: metadataCopyScheme
        )
        await AudioFormatConverter(source: convSource).copyMetadata()

        // Re-write markers adjusted for the trim range, overwriting the unadjusted markers
        // that copyMetadata wrote above.
        if metadataCopyScheme.includesMarkers, edit.trim.inPoint > 0 || edit.trim.outPoint > 0 {
            let renderedDuration = Double(processed.frameLength) / processed.format.sampleRate
            await adjustAndWriteMarkers(to: resolvedOutput, newDuration: renderedDuration)
        }

        return resolvedOutput
    }

    // MARK: - Private

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
            try await writeViaIntermediateWAV(buffer, sampleRate: fileFormat.sampleRate, to: url)
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

    private func writeViaIntermediateWAV(
        _ buffer: AVAudioPCMBuffer,
        sampleRate: Double,
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
            options: AudioFormatConverterOptions(),
            metadataCopyScheme: .ignore
        )

        try await AudioFormatConverter(source: convSource).start()
    }

    private static func isDirectlyWritable(url: URL) -> Bool {
        AudioFileType(pathExtension: url.pathExtension)?.isAVAudioFileWritable ?? true
    }

    /// Reads the source's markers, moves them onto the trimmed timeline, and re-writes them to
    /// `outputURL`, overwriting the unadjusted markers `copyMetadata` already wrote.
    ///
    /// - Parameter newDuration: duration of the render, bounding a region that ran past the
    ///   out-point.
    private func adjustAndWriteMarkers(to outputURL: URL, newDuration: TimeInterval) async {
        guard let outputType = AudioFileType(pathExtension: outputURL.pathExtension) else { return }

        let collection: AudioMarkerDescriptionCollection
        do {
            collection = try await AudioMarkerDescriptionCollection(url: sourceURL)
        } catch {
            return
        }

        guard collection.count > 0 else { return }

        let adjusted = AudioMarkerDescription.adjustedForTrim(
            collection.markerDescriptions,
            inPoint: edit.trim.inPoint,
            outPoint: edit.trim.outPoint,
            newDuration: newDuration
        )

        // An empty set has to clear the file rather than skip it: `copyMetadata` already wrote the
        // source's markers at their pre-trim times, and leaving them is worse than having none.
        guard adjusted.isNotEmpty else {
            AudioFormatConverter.removeMarkers(from: outputURL, outputType: outputType)
            return
        }

        AudioFormatConverter.writeMarkers(adjusted, to: outputURL, outputType: outputType)
    }
}
