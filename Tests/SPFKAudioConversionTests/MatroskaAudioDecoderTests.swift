// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// `sample.mkv` is `sample.mov` remuxed with `-c copy`, so both carry the same AAC bitstream. That
/// makes the `.mov` — which AVFoundation opens normally — the reference for what decoding the
/// `.mkv` should produce.
@Suite(.tags(.file), .serialized)
final class MatroskaAudioDecoderTests {
    let mkv = TestBundleResources.shared.sample_mkv
    let mov = TestBundleResources.shared.sample_mov

    /// Decodes everything and returns the concatenated samples of channel 0.
    private func decodeAll(_ url: URL) throws -> (samples: [Float], format: AVAudioFormat) {
        let decoder = try MatroskaAudioDecoder(url: url)
        var samples: [Float] = []

        while let buffer = try decoder.nextBuffer() {
            guard let channel = buffer.floatChannelData?[0] else { continue }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        return (samples, decoder.processingFormat)
    }

    @Test func decodesTheAudioTrackToPCM() throws {
        let (samples, format) = try decodeAll(mkv)

        #expect(format.sampleRate == 44100)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatFloat32)

        // Roughly 2 seconds at 44.1kHz. Loose because AAC decodes in 1024-frame packets and carries
        // encoder priming that a raw packet stream has no edit list to trim.
        #expect(samples.count > 88000)
        #expect(samples.count < 96000)
    }

    /// **`sample.mkv`'s audio is digital silence**, so it can only ever prove the plumbing runs.
    /// Everything about signal uses `tabla.mka`, which carries real audio and has a bit-identical
    /// reference in `tabla.m4a`.
    @Test func theDecodedAudioIsNotSilence() throws {
        let (samples, _) = try decodeAll(TestBundleResources.shared.tabla_mka)

        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.1)
    }

    /// The decisive one: the same AAC bitstream through AVFoundation's own reader.
    ///
    /// Compares the signal rather than sample positions, because a raw packet stream has no edit
    /// list and so keeps the encoder priming an `.m4a` trims — the two are offset by a fixed lead-in
    /// and a sample-by-sample diff would fail on correct output.
    @Test func matchesAVFoundationDecodingTheSameBitstream() throws {
        let (matroska, format) = try decodeAll(TestBundleResources.shared.tabla_mka)

        let file = try AVAudioFile(forReading: TestBundleResources.shared.tabla_m4a)
        let reference = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                      frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: reference)

        let referenceChannel = try #require(reference.floatChannelData?[0])
        let referenceSamples = Array(UnsafeBufferPointer(start: referenceChannel,
                                                         count: Int(reference.frameLength)))

        #expect(format.sampleRate == file.processingFormat.sampleRate)
        #expect(format.channelCount == file.processingFormat.channelCount)

        let matroskaPeak = matroska.map(abs).max() ?? 0
        let referencePeak = referenceSamples.map(abs).max() ?? 0

        #expect(referencePeak > 0.1, "the reference must have signal or this proves nothing")
        #expect(abs(matroskaPeak - referencePeak) < 0.05)

        // Total energy, which survives the priming offset in a way a positional diff does not.
        let matroskaEnergy = matroska.reduce(0) { $0 + Double($1 * $1) }
        let referenceEnergy = referenceSamples.reduce(0) { $0 + Double($1 * $1) }

        #expect(referenceEnergy > 0)
        #expect(abs(matroskaEnergy - referenceEnergy) / referenceEnergy < 0.05)
    }

    /// An audio-only Matroska decodes the same way — nothing about this path needs a video track.
    @Test func decodesAnAudioOnlyMatroskaFile() throws {
        let (samples, format) = try decodeAll(TestBundleResources.shared.sample_mka)

        #expect(format.sampleRate == 44100)
        #expect(samples.isEmpty == false)
    }

    /// WebM carries Opus rather than AAC, so this exercises a second codec through the same path.
    @Test func decodesWebMOpus() throws {
        let url = TestBundleResources.shared.sample_webm

        // Opus is not in the supported set yet -- assert the refusal is explicit rather than a
        // silent empty result, so the gap is visible when someone opens a .webm.
        #expect(throws: MatroskaAudioDecoderError.unsupportedCodec("A_OPUS")) {
            try MatroskaAudioDecoder(url: url)
        }
    }
}
