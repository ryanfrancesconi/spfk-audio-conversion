// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase

/// Converts audio files between PCM and compressed formats using CoreAudio and AVFoundation.
///
/// Create a converter with an input URL, output URL, and optional ``AudioFormatConverterOptions``,
/// then call ``start()`` to perform the conversion. The output format is determined by the file
/// extension and options.
public class AudioFormatConverter {
    /// The source, destination, and options for this conversion.
    public var source: AudioFormatConverterSource

    /// Creates a converter with explicit input and output URLs.
    /// - Parameters:
    ///   - inputURL: The audio file to read.
    ///   - outputURL: The destination URL for the converted file.
    ///   - options: Conversion options. Pass `nil` to use defaults (format inferred from output extension).
    public convenience init(inputURL: URL, outputURL: URL, options: AudioFormatConverterOptions? = nil) {
        let options = options ?? AudioFormatConverterOptions()
        let source = AudioFormatConverterSource(input: inputURL, output: outputURL, options: options)
        self.init(source: source)
    }

    /// Creates a converter from a pre-configured source.
    /// - Parameter source: The source describing input, output, and options.
    public init(source: AudioFormatConverterSource) {
        self.source = source
    }

    // MARK: -

    /// Performs the conversion, routing through the appropriate pipeline based on input/output formats.
    ///
    /// - PCM output → `ExtAudioFile` (CoreAudio)
    /// - FLAC / OGG / MP3 output → libsndfile / LAME (direct)
    /// - PCM-to-compressed → `AVAssetWriter` (AVFoundation)
    /// - Compressed-to-compressed → intermediate PCM then `AVAssetWriter`
    public func start() async throws {
        try Task.checkCancellation()

        let inputFormat: AudioFileType? =
            if source.input.pathExtension == "",
                let ext = (try? AudioFileType.getExtensions(for: source.input))?.first
            {
                AudioFileType(pathExtension: ext)

            } else {
                AudioFileType(pathExtension: source.input.pathExtension)
            }

        // verify inputFormat, only allow files with path extensions for speed?
        guard let inputFormat, AudioFormatConverter.inputFormats.contains(inputFormat) else {
            throw NSError(
                description:
                    "The input file format (\(source.input.lastPathComponent)) is in an incompatible format: \(inputFormat?.rawValue ?? "nil")"
            )
        }

        if source.output.exists {
            if source.options.eraseFile {
                try FileManager.default.removeItem(at: source.output)
                Log.debug("eraseFile == true, removed existing file at", source.output.path)

            } else {
                let message = "The output file exists already. You need to choose a unique URL or delete the file."
                throw NSError(description: message)
            }
        }

        if source.options.format == nil {
            source.options.format = AudioFileType(pathExtension: source.output.pathExtension)
        }

        let outputFormat = AudioFileType(pathExtension: source.output.pathExtension)

        // Format checks are necessary as AVAssetReader has opinions about compressed

        do {
            // PCM output, any supported input
            if Self.isPCM(url: source.output) == true {
                try await convertToPCM()

                // Direct conversion formats: MP3 (LAME), FLAC, OGG (libsndfile)
            } else if let outputFormat, Self.directConversionFormats.contains(outputFormat) {
                try await convertCompressed()

                // PCM input, compressed output (AVAssetWriter)
            } else if Self.isPCM(url: source.input) == true,
                Self.isCompressed(url: source.output) == true
            {
                try await AssetWriter(source: source).start()

                // Compressed input and output (intermediate PCM then AVAssetWriter)
            } else if Self.isCompressed(url: source.input) == true,
                Self.isCompressed(url: source.output) == true
            {
                try await convertCompressed()

            } else {
                throw NSError(description: "Unable to determine formats for conversion")
            }

        } catch is CancellationError {
            // Clean up partial output file
            if source.output.exists {
                try? FileManager.default.removeItem(at: source.output)
            }

            throw CancellationError()
        }
        
        await copyMetadata()
    }
}
