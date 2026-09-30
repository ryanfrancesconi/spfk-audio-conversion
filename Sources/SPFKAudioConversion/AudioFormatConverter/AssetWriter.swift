// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase

/// Writes AAC (M4A, MP4) using AVFoundation's `AVAssetWriter` pipeline. PCM output is
/// ``AudioFormatConverter``'s own `ExtAudioFile` path.
///
/// Accepts PCM input only. For compressed input, first convert to an intermediate PCM file.
actor AssetWriter {
    /// The conversion source describing input, output, and options.
    var source: AudioFormatConverterSource

    init(source: AudioFormatConverterSource) {
        self.source = source
    }

    /// The AVFoundation way. *This doesn't currently handle compressed input - only compressed output.*
    func start() async throws {
        guard let outputFormat = source.options.format else {
            throw NSError(description: "Options format can't be nil.")
        }

        // verify outputFormat
        guard AudioFormatConverter.outputFormats.contains(outputFormat) else {
            throw NSError(description: "The output file format isn't able to be produced by this class.")
        }

        switch outputFormat {
        case .m4a, .mp4:
            break
        default:
            throw NSError(description: "Unsupported output format: \(outputFormat)")
        }

        guard let fileType = outputFormat.avFileType else {
            throw NSError(description: "Unsupported output format: \(outputFormat)")
        }

        // Capture once — source.asset is a computed property that creates a new AVURLAsset each call.
        // The reader, track, and format hint must all reference the same asset instance.
        let asset = source.asset

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(description: "No audio was found in the input file.")
        }

        let outputSettings = try await createOutputSettings(for: asset)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: source.output, fileType: fileType)

        let assetFormat = await asset.audioFormat

        let writerInput = AVAssetWriterInput(
            mediaType: .audio, outputSettings: outputSettings,
            sourceFormatHint: assetFormat?.formatDescription
        )
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let container = AssetWriterContainer(
            reader: reader, writer: writer, writerInput: writerInput, readerOutput: readerOutput
        )

        try await container.start()
    }

    private func createOutputSettings(for asset: AVURLAsset) async throws -> [String: Any] {
        guard let inputFormat = await asset.audioFormat else {
            throw NSError(description: "Unable to read the input file format.")
        }

        guard let outputFormat = source.options.format else {
            throw NSError(description: "Options format can't be nil.")
        }

        guard let formatKey = outputFormat.audioFormatID, formatKey == kAudioFormatMPEG4AAC else {
            throw NSError(description: "Unsupported output format: \(outputFormat)")
        }

        var sampleRate = source.options.sampleRate ?? inputFormat.sampleRate
        let channels = source.options.channels ?? inputFormat.channelCount

        if sampleRate == 0 {
            let systemRate = await AudioDefaults.shared.sampleRate
            Log.error(
                "Sample rate can't be 0 - assigning to default format of \(systemRate). inputFormat is", inputFormat
            )
            sampleRate = systemRate
        }

        // AAC encodes nothing above 48 kHz.
        if sampleRate > 48000 {
            source.adjustments.append(
                .sampleRate(requested: sampleRate, applied: 48000, format: outputFormat)
            )
            sampleRate = 48000
        }

        // mono should be 1/2 the shown bitrate
        let perChannel = channels == 1 ? 2 : 1

        return [
            AVFormatIDKey: formatKey,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: Int(source.options.bitRate) / perChannel,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
        ]
    }
}
