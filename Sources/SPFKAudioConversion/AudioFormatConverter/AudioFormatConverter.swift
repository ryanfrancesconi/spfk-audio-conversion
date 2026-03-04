// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase

/// AudioFormatConverter wraps the more complex AVFoundation and CoreAudio audio conversions in an easy to use format.
public class AudioFormatConverter {
    public var source: AudioFormatConverterSource

    public convenience init(inputURL: URL, outputURL: URL, options: AudioFormatConverterOptions? = nil) {
        let options = options ?? AudioFormatConverterOptions()
        let source = AudioFormatConverterSource(input: inputURL, output: outputURL, options: options)
        self.init(source: source)
    }

    /// init with input, output and options - then start()
    public init(source: AudioFormatConverterSource) {
        self.source = source
    }

    // MARK: -

    /// The entry point for file conversion
    public func start() async throws {
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

        // Format checks are necessary as AVAssetReader has opinions about compressed

        // PCM output, any supported input
        if Self.isPCM(url: source.output) == true {
            // PCM output
            try await convertToPCM()

            // special case for MP3 files
        } else if source.output.pathExtension.lowercased() == AudioFileType.mp3.pathExtension {
            try await convertToMP3()

            // PCM input, compressed output
        } else if Self.isPCM(url: source.input) == true,
            Self.isCompressed(url: source.output) == true
        {
            try await AssetWriter(source: source).start()

            // Compressed input and output
        } else if Self.isCompressed(url: source.input) == true,
            Self.isCompressed(url: source.output) == true
        {
            try await convertCompressed()

        } else {
            throw NSError(description: "Unable to determine formats for conversion")
        }
    }
}
