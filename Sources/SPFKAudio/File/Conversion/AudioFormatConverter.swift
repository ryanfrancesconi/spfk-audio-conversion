// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

/// AudioFormatConverter wraps the more complex AVFoundation and CoreAudio audio conversions in an easy to use format.
public class AudioFormatConverter {
    /// - Parameter: error This will contain one parameter of type Error which is nil if the conversion was successful.
    public typealias Callback = (_ error: Error?) -> Void

    // MARK: - properties

    /// The source audio file
    public var inputURL: URL?

    /// The audio file to be created after conversion
    public var outputURL: URL?

    /// Options for conversion
    public var options: AudioFormatConverterOptions?

    // MARK: - private properties

    let sox = SoX()

    // The reader needs to exist outside the start func otherwise the async nature of the
    // AVAssetWriterInput will lose its reference
    var reader: AVAssetReader?
    var writer: AVAssetWriter?

    // MARK: - initialization

    /// init with input, output and options - then start()
    public init(
        inputURL: URL,
        outputURL: URL,
        options: AudioFormatConverterOptions? = nil
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.options = options ?? AudioFormatConverterOptions()
    }

    deinit {
        reader = nil
        writer = nil
        inputURL = nil
        outputURL = nil
        options = nil
    }

    // MARK: - Async

    /// The entry point for file conversionÏ
    public func start() async throws {
        try await process()
    }

    // MARK: Legacy

    /// The entry point for file conversion
    /// - Parameter completionHandler: the callback that will be triggered when process has completed.
    public func start(completionHandler: Callback? = nil) {
        Task {
            do {
                try await self.process()

                Task { @MainActor in
                    completionHandler?(nil)
                }

            } catch {
                Task { @MainActor in
                    completionHandler?(error)
                }
            }
        }
    }

    // MARK: -

    private func process() async throws {
        guard let inputURL else {
            throw NSError(description: "Input file can't be nil.")
        }

        guard let outputURL else {
            throw NSError(description: "Output file can't be nil.")
        }

        var inputFormat: AudioFileType

        if inputURL.pathExtension == "",
           let ext = (try? MetaAudioFileFormat.getExtensions(for: inputURL))?.first {
            inputFormat = AudioFileType(pathExtension: ext)

        } else {
            inputFormat = AudioFileType(pathExtension: inputURL.pathExtension)
        }

        // verify inputFormat, only allow files with path extensions for speed?
        guard AudioFormatConverter.inputFormats.contains(inputFormat) else {
            throw NSError(description: "The input file format is in an incompatible format: \(inputFormat)")
        }

        if outputURL.exists {
            if options?.eraseFile == true {
                try FileManager.default.removeItem(at: outputURL)
                Log.debug("eraseFile == true, removed existing file at", outputURL.path)

            } else {
                let message = "The output file exists already. You need to choose a unique URL or delete the file."
                throw NSError(description: message)
            }
        }

        if options?.format == nil {
            options?.format = AudioFileType(pathExtension: outputURL.pathExtension)
        }

        // Format checks are necessary as AVAssetReader has opinions about compressed

        // PCM output, any supported input
        if Self.isPCM(url: outputURL) == true {
            // PCM output
            try await convertToPCM()

        } else if outputURL.pathExtension.lowercased() == "mp3" {
            try await convertToMP3()

            // PCM input, compressed output
        } else if Self.isPCM(url: inputURL) == true,
                  Self.isCompressed(url: outputURL) == true {
            try await convertPCMToCompressed()

            // Compressed input and output, won't do sample rate
        } else if Self.isCompressed(url: inputURL) == true,
                  Self.isCompressed(url: outputURL) == true {
            try await convertCompressed()

        } else {
            throw NSError(description: "Unable to determine formats for conversion")
        }
    }
}
