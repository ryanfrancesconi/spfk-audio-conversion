// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem

/// Converts audio files between PCM and compressed formats using CoreAudio and AVFoundation.
///
/// Create a converter with an input URL, output URL, and optional ``AudioFormatConverterOptions``,
/// then call ``start()`` to perform the conversion. The output format is determined by the file
/// extension and options.
public actor AudioFormatConverter {
    /// The source, destination, and options for this conversion.
    ///
    /// Read it back after ``start()``: a `.unique` output conflict and anything the output format
    /// could not honor are recorded here rather than on the copy a caller passed in.
    public var source: AudioFormatConverterSource

    /// Creates a converter with explicit input and output URLs.
    /// - Parameters:
    ///   - inputURL: The audio file to read.
    ///   - outputURL: The destination URL for the converted file.
    ///   - options: Conversion options. Pass `nil` to use defaults (format inferred from output extension).
    public init(inputURL: URL, outputURL: URL, options: AudioFormatConverterOptions? = nil) {
        let options = options ?? AudioFormatConverterOptions()
        source = AudioFormatConverterSource(input: inputURL, output: outputURL, options: options)
    }

    /// Creates a converter from a pre-configured source.
    /// - Parameter source: The source describing input, output, and options.
    public init(source: AudioFormatConverterSource) {
        self.source = source
    }

    // Set to true by convertToPCM() when it takes the same-format copy path instead of
    // re-encoding. A verbatim file copy already contains all source metadata, so
    // copyMetadata() must be skipped to avoid TagLib rewriting (and altering) the output.
    var didFileCopy = false

    // MARK: -

    /// Performs the conversion, routing through the appropriate pipeline based on input/output formats.
    ///
    /// - Matroska input, or an audio track that is not the container's first → decoded here to an
    ///   intermediate WAV and converted from that
    /// - PCM output → `ExtAudioFile` (CoreAudio)
    /// - FLAC / OGG / MP3 output → libsndfile / LAME (direct)
    /// - PCM-to-compressed → `AVAssetWriter` (AVFoundation)
    /// - Compressed-to-compressed → intermediate PCM then `AVAssetWriter`
    public func start() async throws {
        try Task.checkCancellation()

        let inputURL = source.input
        try await inputURL.withSecurityScopedAccess {
            let inputFormat: AudioFileType? =
                if source.input.pathExtension == "",
                let ext = (try? AudioFileType.getExtensions(for: source.input))?.first {
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

            // Matroska is opaque to both Core Audio and AVFoundation, so it is demuxed to an
            // intermediate WAV and converted from there rather than routed below.
            if inputFormat.isMatroska {
                try await convertFromMatroska()
                return
            }

            // Everything below decodes whichever audio track the container lists first, so a
            // selection naming any other one is decoded here and converted from the result.
            if await requiresTrackDemux() {
                try await convertSelectedAudioTrack()
                return
            }

            if source.output.exists {
                switch source.options.conflictScheme {
                case .overwrite:
                    try FileManager.default.removeItem(at: source.output)
                    Log.debug("eraseFile == true, removed existing file at", source.output.path)

                case .error:
                    let message = "The output file exists already. You need to choose a unique URL or delete the file."
                    throw NSError(description: message)

                case .unique:
                    source.output = FileSystem.nextAvailableURL(source.output)
                }
            }

            if source.options.format == nil {
                source.options.format = AudioFileType(pathExtension: source.output.pathExtension)
            }

            // An unsupported format is rejected by the options setter, so nothing below can say
            // what was asked for.
            guard source.options.format != nil else {
                throw NSError(
                    description:
                    "\(source.output.pathExtension.uppercased()) is not a format this converter writes. It writes \(AudioFormatConverterOptions.supportedOutputFormatsString)."
                )
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
                    let writer = AssetWriter(source: source)
                    try await writer.start()

                    // The writer holds its own copy of the source, so what the output format could
                    // not honor is recorded there.
                    source.adjustments = await writer.source.adjustments

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

            if !didFileCopy {
                await copyMetadata()
            }
        }
    }
}
