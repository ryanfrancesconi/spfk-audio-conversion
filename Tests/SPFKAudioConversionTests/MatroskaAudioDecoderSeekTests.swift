// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// Seeking is what makes the decoder usable for playback rather than only for a front-to-back
/// waveform scan, so the thing under test is that a seek lands where it says it does.
///
/// The reference is the *same decoder* read sequentially. Comparing against an `AVAudioFile` of the
/// same bitstream would fold in the encoder-priming offset an `.m4a` edit list trims and a raw
/// packet stream keeps, which is a real difference but not this one.
///
/// `tabla.mka` throughout: `sample.mkv`'s audio is digital silence, and silence cannot show that a
/// seek landed in the wrong place.
@Suite(.tags(.file), .serialized)
final class MatroskaAudioDecoderSeekTests {
    let url = TestBundleResources.shared.tabla_mka

    /// Every sample of channel 0, read through the same buffered path a seek uses.
    private func readAll(_ url: URL) throws -> (samples: [Float], format: AVAudioFormat) {
        let decoder = try MatroskaAudioDecoder(url: url)
        let chunk: AVAudioFrameCount = 4096

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: chunk)
        )

        var samples: [Float] = []

        while try decoder.readNextChunk(into: buffer, frameCount: chunk) > 0 {
            samples.append(contentsOf: channelSamples(buffer))
        }

        return (samples, decoder.processingFormat)
    }

    private func channelSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }

        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Where in `reference` the `window` actually sits, relative to `expected`.
    ///
    /// Reported rather than merely compared because a mismatch here is always a boundary — a packet,
    /// a cluster, or the codec's priming — and the offset names which one. An assertion that the
    /// two "are not equal" would send the next reader hunting for a precision bug instead.
    private func alignmentOffset(
        of window: [Float],
        in reference: [Float],
        expectedAt expected: Int,
        search: Int
    ) -> Int {
        let length = min(512, window.count)

        guard length > 0 else { return 0 }

        var bestOffset = 0
        var bestError = Float.greatestFiniteMagnitude

        for offset in -search ... search {
            let start = expected + offset

            guard start >= 0, start + length <= reference.count else { continue }

            var error: Float = 0

            for index in 0 ..< length {
                let delta = window[index] - reference[start + index]
                error += delta * delta
            }

            if error < bestError {
                bestError = error
                bestOffset = offset
            }
        }

        return bestOffset
    }

    @Test func seekLandsOnTheSameSamplesAsReadingThere() throws {
        let (reference, format) = try readAll(url)

        // One second in, far enough to be past the first cluster and the codec's priming.
        let target = AVAudioFramePosition(format.sampleRate)
        let count: AVAudioFrameCount = 4096

        try #require(reference.count > Int(target) + Int(count))

        let decoder = try MatroskaAudioDecoder(url: url)
        try decoder.seek(toFrame: target)

        #expect(decoder.framePosition == target)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: count)
        )

        let written = try decoder.readNextChunk(into: buffer, frameCount: count)
        #expect(written == count)

        let seeked = channelSamples(buffer)

        // The reference has real signal here, or matching it would prove nothing.
        let peak = seeked.map(abs).max() ?? 0
        #expect(peak > 0.01, "seeked to a silent region — this test cannot detect misalignment there")

        let offset = alignmentOffset(of: seeked, in: reference, expectedAt: Int(target), search: 4096)
        #expect(offset == 0, "seeked audio best matches the sequential read at offset \(offset)")
    }

    /// A target inside the preroll, so the seek clamps to the start of the file and the discard is
    /// the whole distance rather than the preroll. A distinct path from a mid-file seek, and the one
    /// a user hits by dragging the playhead near the beginning.
    @Test func seekLandsExactlyWhenTheTargetIsInsideThePreroll() throws {
        let (reference, format) = try readAll(url)

        let target = AVAudioFramePosition(format.sampleRate * 0.5)
        let count: AVAudioFrameCount = 4096

        try #require(reference.count > Int(target) + Int(count))

        let decoder = try MatroskaAudioDecoder(url: url)
        try decoder.seek(toFrame: target)

        #expect(decoder.framePosition == target)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: count)
        )

        let written = try decoder.readNextChunk(into: buffer, frameCount: count)
        #expect(written == count)

        let offset = alignmentOffset(of: channelSamples(buffer), in: reference, expectedAt: Int(target), search: 4096)

        #expect(offset == 0, "seeking to 0.5s best matches the sequential read at offset \(offset)")
    }

    @Test func framePositionAdvancesWithReads() throws {
        let decoder = try MatroskaAudioDecoder(url: url)
        let count: AVAudioFrameCount = 4096

        #expect(decoder.framePosition == 0)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: count)
        )

        let written = try decoder.readNextChunk(into: buffer, frameCount: count)

        #expect(written == count)
        #expect(decoder.framePosition == AVAudioFramePosition(count))
    }

    /// Backwards is the case a scrubber hits constantly and the one a streamed decoder cannot do by
    /// continuing to read.
    @Test func seeksBackwardAsWellAsForward() throws {
        let (reference, format) = try readAll(url)

        let far = AVAudioFramePosition(format.sampleRate * 1.5)
        let near = AVAudioFramePosition(format.sampleRate * 0.5)
        let count: AVAudioFrameCount = 2048

        try #require(reference.count > Int(far) + Int(count))

        let decoder = try MatroskaAudioDecoder(url: url)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: count)
        )

        try decoder.seek(toFrame: far)
        _ = try decoder.readNextChunk(into: buffer, frameCount: count)

        try decoder.seek(toFrame: near)
        #expect(decoder.framePosition == near)

        let written = try decoder.readNextChunk(into: buffer, frameCount: count)
        #expect(written == count)

        let offset = alignmentOffset(
            of: channelSamples(buffer),
            in: reference,
            expectedAt: Int(near),
            search: 4096
        )

        #expect(offset == 0, "backward seek best matches the sequential read at offset \(offset)")
    }

    @Test func seekToZeroReturnsToTheStart() throws {
        let (reference, _) = try readAll(url)

        let count: AVAudioFrameCount = 2048
        let decoder = try MatroskaAudioDecoder(url: url)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: count)
        )

        try decoder.seek(toFrame: AVAudioFramePosition(44100))
        _ = try decoder.readNextChunk(into: buffer, frameCount: count)

        try decoder.seek(toFrame: 0)
        #expect(decoder.framePosition == 0)

        let written = try decoder.readNextChunk(into: buffer, frameCount: count)
        #expect(written == count)

        let samples = channelSamples(buffer)
        let expected = Array(reference[0 ..< samples.count])
        let maxDelta = zip(samples, expected).map { abs($0 - $1) }.max() ?? 1

        #expect(maxDelta < 0.01, "rewinding to zero did not reproduce the start of the file")
    }

    /// Past the end is a read of nothing, not a throw — a scrubber dragged to the very end should
    /// stop producing audio rather than report a failure.
    @Test func seekingPastTheEndReadsNothing() throws {
        let decoder = try MatroskaAudioDecoder(url: url)
        let count: AVAudioFrameCount = 1024

        try decoder.seek(toFrame: decoder.totalFrameCount * 4)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: count)
        )

        #expect(try decoder.readNextChunk(into: buffer, frameCount: count) == 0)
    }

    /// An audio-only container seeks by the same path — nothing here needs a video track, and the
    /// `Cues` index of a `.mka` indexes a different track than the one `.mkv` tests exercise.
    @Test func seeksInAnAudioOnlyMatroskaFile() throws {
        let decoder = try MatroskaAudioDecoder(url: TestBundleResources.shared.sample_mka)
        let target = AVAudioFramePosition(decoder.processingFormat.sampleRate * 0.5)

        try decoder.seek(toFrame: target)

        #expect(decoder.framePosition == target)
    }
}
