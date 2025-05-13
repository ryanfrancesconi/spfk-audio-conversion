// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

/// AudioFormatConverter wraps the more complex AVFoundation and CoreAudio audio conversions in an easy to use format.
public class AudioFormatConverter {
    public var source: AudioFormatConverterSource

    // MARK: - private properties

    // The reader needs to exist outside the start func otherwise the async nature of the
    // AVAssetWriterInput will lose its reference
    var reader: AVAssetReader?
    var writer: AVAssetWriter?

    // MARK: - initialization

    public convenience init(inputURL: URL, outputURL: URL, options: AudioFormatConverterOptions? = nil) {
        let options = options ?? AudioFormatConverterOptions()
        let source = AudioFormatConverterSource(input: inputURL, output: outputURL, options: options)
        self.init(source: source)
    }

    /// init with input, output and options - then start()
    public init(source: AudioFormatConverterSource) {
        self.source = source
    }

    deinit {
        reader = nil
        writer = nil
    }

    // MARK: -

    /// The entry point for file conversionÏ
    public func start() async throws {
        var inputFormat: AudioFileType

        if source.input.pathExtension == "",
           let ext = (try? MetaAudioFileFormat.getExtensions(for: source.input))?.first {
            inputFormat = AudioFileType(pathExtension: ext)

        } else {
            inputFormat = AudioFileType(pathExtension: source.input.pathExtension)
        }

        // verify inputFormat, only allow files with path extensions for speed?
        guard AudioFormatConverter.inputFormats.contains(inputFormat) else {
            throw NSError(description: "The input file format is in an incompatible format: \(inputFormat)")
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
                  Self.isCompressed(url: source.output) == true {
            try await convertPCMToCompressed()

            // Compressed input and output
        } else if Self.isCompressed(url: source.input) == true,
                  Self.isCompressed(url: source.output) == true {
            try await convertCompressed()

        } else {
            throw NSError(description: "Unable to determine formats for conversion")
        }
    }
}
