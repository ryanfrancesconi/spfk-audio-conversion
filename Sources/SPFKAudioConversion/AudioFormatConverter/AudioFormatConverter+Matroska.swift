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
    /// - Throws: ``MatroskaAudioDecoderError`` naming the codec when the track is one macOS has no
    ///   decoder for, which is the only refusal this path should produce.
    func convertFromMatroska() async throws {
        try Task.checkCancellation()

        let decoder = try MatroskaAudioDecoder(url: source.input, audioTrack: source.audioTrack)

        try await convertViaIntermediate(
            pcmSource: decoder,
            sampleFormat: Self.intermediateSampleFormat(for: decoder.track)
        )
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
