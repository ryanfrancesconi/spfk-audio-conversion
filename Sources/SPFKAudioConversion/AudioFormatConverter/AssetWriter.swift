// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase

/// Writes audio to compressed or PCM formats using AVFoundation's `AVAssetWriter` pipeline.
///
/// Accepts PCM input only. For compressed input, first convert to an intermediate PCM file.
public actor AssetWriter {
    /// The conversion source describing input, output, and options.
    public var source: AudioFormatConverterSource

    init(source: AudioFormatConverterSource) {
        self.source = source
    }

    /// The AVFoundation way. *This doesn't currently handle compressed input - only compressed output.*
    public func start() async throws {
        guard let outputFormat = source.options.format else {
            throw NSError(description: "Options format can't be nil.")
        }

        // verify outputFormat
        guard AudioFormatConverter.outputFormats.contains(outputFormat) else {
            throw NSError(description: "The output file format isn't able to be produced by this class.")
        }

        switch outputFormat {
        case .m4a, .mp4, .aiff, .caf, .wav:
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

        guard let fileType = outputFormat.avFileType, let formatKey = outputFormat.audioFormatID
        else {
            throw NSError(description: "Unsupported output format: \(outputFormat)")
        }

        // 1. chosen option. 2. same as input file. 3. 16 bit
        // optional in case of compressed audio. That said, the other conversion methods are actually used in
        // that case
        let bitDepth = (source.options.bitsPerChannel ?? inputFormat.settings[AVLinearPCMBitDepthKey] ?? 16) as Any

        var isFloat = false

        if let intDepth = bitDepth as? Int {
            isFloat = intDepth >= 32
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

        // Note: AVAssetReaderOutput does not currently support compressed audio
        if formatKey == kAudioFormatMPEG4AAC {
            if sampleRate > 48000 {
                sampleRate = 48000
            }

            // mono should be 1/2 the shown bitrate
            let perChannel = channels == 1 ? 2 : 1

            // reset these for m4a:
            return [
                AVFormatIDKey: formatKey,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: Int(source.options.bitRate) / perChannel,
                AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
            ]

        } else {
            return [
                AVFormatIDKey: formatKey,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: bitDepth,
                AVLinearPCMIsFloatKey: isFloat,
                AVLinearPCMIsBigEndianKey: fileType == .aiff,
                AVLinearPCMIsNonInterleaved: !(source.options.isInterleaved ?? inputFormat.isInterleaved),
            ]
        }
    }
}
