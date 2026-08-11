// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMatroska
import SPFKUtils
import SPFKVideo

extension AudioFormatConverter {
    /// Converts a Matroska-family input by demuxing its audio to an intermediate WAV first.
    ///
    /// Neither `ExtAudioFile` nor `AVAssetReader` opens the container, so all three routes through
    /// ``start()`` fail on one. ``MatroskaAudioDecoder`` supplies PCM the rest of the pipeline reads
    /// as it would any other WAV, which is what makes a video source with an audio target work.
    ///
    /// Metadata is copied from the original rather than the intermediate: TagLib reads the container
    /// directly, and the intermediate carries none of it.
    func convertFromMatroska() async throws {
        try Task.checkCancellation()

        let intermediate = try await demuxToWAV(directory: source.output.deletingLastPathComponent())

        defer {
            Log.debug("Removing intermediate file at", intermediate.path)
            try? intermediate.delete()
        }

        var innerSource = source
        innerSource.input = intermediate
        innerSource.metadataCopyScheme = .ignore

        let converter = AudioFormatConverter(source: innerSource)
        try await converter.start()

        // `start()` resolves a `.unique` output conflict and records the options the format could
        // not honor, both on its own copy of the source. A caller reading either off this converter
        // gets the intermediate run's answer only if they are carried back.
        source.output = converter.source.output
        source.adjustments = converter.source.adjustments

        await copyMetadata()
    }

    /// Decodes the selected audio track into a WAV in `directory`.
    ///
    /// - Throws: ``MatroskaAudioDecoderError`` naming the codec when the track is one macOS has no
    ///   decoder for, which is the only refusal this path should produce.
    private func demuxToWAV(directory: URL) async throws -> URL {
        let decoder = try MatroskaAudioDecoder(url: source.input, audioTrack: source.audioTrack)

        let name = source.input.deletingPathExtension().lastPathComponent + "_" + Entropy.uniqueId + ".wav"
        let output = directory.appending(component: name, directoryHint: .notDirectory)

        let sampleFormat = Self.intermediateSampleFormat(for: decoder.track)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: decoder.processingFormat.sampleRate,
            AVNumberOfChannelsKey: decoder.processingFormat.channelCount,
            AVLinearPCMBitDepthKey: sampleFormat.bitDepth,
            AVLinearPCMIsFloatKey: sampleFormat.isFloat,
            AVLinearPCMIsBigEndianKey: false,
        ]

        // The decoder hands back deinterleaved float32 whatever the track's own depth is — that is
        // what `commonFormat` and `interleaved` describe. `settings` describes the file on disk.
        var file: AVAudioFile? = try AVAudioFile(
            forWriting: output,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var writtenFrames: AVAudioFramePosition = 0

        do {
            while let buffer = try decoder.nextBuffer() {
                try Task.checkCancellation()

                try file?.write(from: buffer)
                writtenFrames += AVAudioFramePosition(buffer.frameLength)
            }
        } catch {
            file = nil
            try? output.delete()
            throw error
        }

        // Released here rather than at scope exit: a RIFF header states its chunk sizes, and they
        // are written when the file object goes away.
        file = nil

        guard writtenFrames > 0 else {
            try? output.delete()
            throw NSError(description: "No audio could be decoded from \(source.input.lastPathComponent)")
        }

        return output
    }

    /// Sample format for the intermediate, taken from the track where it states one.
    ///
    /// Downstream reads its source depth off this file, so ``AudioFormatConverterOptions/bitDepthRule``
    /// compares the caller's request against this number — a narrower intermediate silently caps
    /// what the output can be. 24-bit covers a lossy codec, which states no depth of its own.
    private static func intermediateSampleFormat(for track: MatroskaTrack) -> (bitDepth: Int, isFloat: Bool) {
        guard case let .audio(parameters) = track.kind, let bitDepth = parameters.bitDepth else {
            return (24, false)
        }

        let isFloat = MatroskaAudioCodec(rawValue: track.codecID)?.pcmSampleFormat == .float

        switch bitDepth {
        case 16, 24, 32:
            return (bitDepth, isFloat)

        case 64:
            // The decoder already narrowed to float32, so nothing further is lost here.
            return (32, true)

        default:
            return (24, false)
        }
    }
}
