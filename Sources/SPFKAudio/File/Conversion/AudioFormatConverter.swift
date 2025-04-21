// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
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

    // MARK: - functions

    /// The entry point for file conversion
    /// - Parameter completionHandler: the callback that will be triggered when process has completed.
    public func start(completionHandler: Callback? = nil) {
        guard let inputURL else {
            completionHandler?(Self.createError(message: "Input file can't be nil."))
            return
        }

        guard let outputURL else {
            completionHandler?(Self.createError(message: "Output file can't be nil."))
            return
        }

        let inputFormat = AudioFileType(pathExtension: inputURL.pathExtension)

        // verify inputFormat, only allow files with path extensions for speed?
        guard AudioFormatConverter.inputFormats.contains(inputFormat) else {
            completionHandler?(Self.createError(message: "The input file format is in an incompatible format: \(inputFormat)"))
            return
        }

        if outputURL.exists {
            if options?.eraseFile == true {
                Log.error("Warning: removing existing file at", outputURL.path)
                try? FileManager.default.removeItem(at: outputURL)
            } else {
                let message = "The output file exists already. You need to choose a unique URL or delete the file."
                completionHandler?(Self.createError(message: message))
                return
            }
        }

        if options?.format == nil {
            options?.format = AudioFileType(pathExtension: outputURL.pathExtension)
        }

        // Format checks are necessary as AVAssetReader has opinions about compressed

        // PCM output, any supported input
        if Self.isPCM(url: outputURL) == true {
            // PCM output
            convertToPCM(completionHandler: completionHandler)

        } else if outputURL.pathExtension.lowercased() == "mp3" {
            convertToMP3(completionHandler: completionHandler)

            // PCM input, compressed output
        } else if Self.isPCM(url: inputURL) == true,
                  Self.isCompressed(url: outputURL) == true {
            convertPCMToCompressed(completionHandler: completionHandler)

            // Compressed input and output, won't do sample rate
        } else if Self.isCompressed(url: inputURL) == true,
                  Self.isCompressed(url: outputURL) == true {
            convertCompressed(completionHandler: completionHandler)

        } else {
            completionHandler?(Self.createError(message: "Unable to determine formats for conversion"))
        }
    }

    func completionProxy(error: Error?,
                         deleteOutputOnError: Bool = true,
                         completionHandler: Callback? = nil) {
        guard error != nil,
              deleteOutputOnError,
              let outputURL,
              outputURL.exists else {
            completionHandler?(error)
            return
        }

        do {
            Log.error("Deleting output on error", outputURL.path)
            try FileManager.default.removeItem(at: outputURL)

        } catch {
            Log.error("Failed to remove file", outputURL, error.localizedDescription)
        }

        completionHandler?(error)
    }
}
