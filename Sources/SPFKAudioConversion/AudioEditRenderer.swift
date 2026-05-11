// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem

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

    /// Determines which metadata is copied from the source to the output.
    ///
    /// Defaults to `.copyTextAndMarkers`. Note: marker positions are not adjusted to
    /// account for trimming or reversal — markers outside the rendered time range are
    /// still written to the output as-is.
    public var metadataCopyScheme: MetadataCopyScheme

    /// Determines how to handle an existing file at ``outputURL``. Defaults to `.error`.
    public var fileConflictScheme: FileConflictScheme

    public init(
        sourceURL: URL,
        edit: AudioEditDescription,
        outputURL: URL,
        metadataCopyScheme: MetadataCopyScheme = .copyTextAndMarkers,
        fileConflictScheme: FileConflictScheme = .error
    ) {
        self.sourceURL = sourceURL
        self.edit = edit
        self.outputURL = outputURL
        self.metadataCopyScheme = metadataCopyScheme
        self.fileConflictScheme = fileConflictScheme
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
        let frameCapacity = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCapacity
        ) else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        try audioFile.read(into: buffer)

        let processed = try buffer.applying(edit)

        try await write(processed, fileFormat: audioFile.fileFormat, to: resolvedOutput)

        if metadataCopyScheme != .ignore {
            let convSource = AudioFormatConverterSource(
                input: sourceURL,
                output: resolvedOutput,
                options: AudioFormatConverterOptions(),
                metadataCopyScheme: metadataCopyScheme
            )
            await AudioFormatConverter(source: convSource).copyMetadata()
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
                settings: fileFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try outputFile.write(from: buffer)
        } else {
            try await writeViaIntermediateWAV(buffer, sampleRate: fileFormat.sampleRate, to: url)
        }
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
}
