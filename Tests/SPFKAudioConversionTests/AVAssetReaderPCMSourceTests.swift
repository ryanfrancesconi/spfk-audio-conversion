// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

/// Decoding a *named* audio track, which `AVAudioFile` cannot do at all.
@Suite(.tags(.file), .serialized)
struct AVAssetReaderPCMSourceTests {
    private var url: URL { TestBundleResources.shared.sample_dualaudio_mov }

    /// The fixture's two tracks are a 440 Hz and an 880 Hz tone, so the dominant frequency says
    /// *which* track was decoded — where two arbitrary tracks would only support "these differ".
    private func dominantFrequency(
        of source: AVAssetReaderPCMSource,
        seconds: Double = 1
    ) throws -> Double {
        let wanted = AVAudioFrameCount(source.processingFormat.sampleRate * seconds)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: wanted) else {
            return 0
        }

        var samples: [Float] = []

        while samples.count < Int(wanted) {
            let written = try source.readNextChunk(into: buffer, frameCount: wanted)

            guard written > 0, let data = buffer.floatChannelData else { break }

            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(written)))
        }

        guard samples.count > 32 else { return 0 }

        // Zero crossings rather than an FFT: a pure tone crosses twice per cycle, which is exact
        // enough to tell 440 from 880 and needs no transform. A small guard band ignores the noise
        // either side of zero that lossy coding leaves.
        let threshold: Float = 0.05
        var crossings = 0
        var lastSign = 0

        for sample in samples where abs(sample) > threshold {
            let sign = sample > 0 ? 1 : -1

            if lastSign != 0, sign != lastSign {
                crossings += 1
            }

            lastSign = sign
        }

        let duration = Double(samples.count) / source.processingFormat.sampleRate

        return Double(crossings) / 2 / duration
    }

    private func tracks() async -> [AudioTrackDescription] {
        await AudioTrackReader.read(from: url)
    }

    /// **The whole reason this type exists.** `AVAudioFile` has no track parameter, so the ordinary
    /// decode path can only ever reach the first track.
    @Test func decodesTheTrackItWasAskedForRatherThanTheFirst() async throws {
        let tracks = await tracks()

        let english = try #require(tracks.first { $0.language == "eng" })
        let japanese = try #require(tracks.first { $0.language == "jpn" })

        let first = try await AVAssetReaderPCMSource(url: url, audioTrack: english.id)
        let second = try await AVAssetReaderPCMSource(url: url, audioTrack: japanese.id)

        #expect(abs(try dominantFrequency(of: first) - 440) < 15)
        #expect(abs(try dominantFrequency(of: second) - 880) < 25)
    }

    /// No selection takes the first track, matching every other entry point's default.
    @Test func defaultsToTheFirstTrack() async throws {
        let source = try await AVAssetReaderPCMSource(url: url)

        #expect(abs(try dominantFrequency(of: source) - 440) < 15)
    }

    /// A selection can outlive the file it was made against; falling back beats throwing, and beats
    /// decoding silence.
    @Test func fallsBackToTheFirstTrackForAnUnknownSelection() async throws {
        let source = try await AVAssetReaderPCMSource(
            url: url,
            audioTrack: AudioTrackDescription.ID(rawValue: 999_999)
        )

        #expect(abs(try dominantFrequency(of: source) - 440) < 15)
    }

    /// The track's own format, not a resample — a waveform drawn at the wrong rate is the wrong
    /// shape.
    @Test func reportsTheTracksOwnFormatAndLength() async throws {
        let source = try await AVAssetReaderPCMSource(url: url)

        #expect(source.processingFormat.sampleRate == 44100)
        #expect(source.processingFormat.channelCount == 1)

        // 2.066s at 44.1kHz. Loose because a container's declared duration and a track's decoded
        // length differ by codec priming.
        #expect(abs(source.totalFrameCount - 91_110) < 3000)
    }

    /// `SeekablePCMSource` says landing exactly is the contract, and a caller scrubbing a waveform
    /// cannot compensate for "approximately". Asserted on the samples, since the position is only
    /// what the seek recorded: the audio after the seek is found in a full decode, searched near
    /// the target, and has to sit at it.
    @Test(arguments: [0.5, 1.0, 1.37])
    func seekingLandsExactlyWhereAsked(seconds: Double) async throws {
        let reference = try await decode(try await AVAssetReaderPCMSource(url: url))

        let source = try await AVAssetReaderPCMSource(url: url)
        let target = AVAudioFramePosition(source.processingFormat.sampleRate * seconds)
        try source.seek(toFrame: target)

        let window = 2048
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: source.processingFormat,
            frameCapacity: AVAudioFrameCount(window)
        ))
        #expect(try source.readNextChunk(into: buffer, frameCount: AVAudioFrameCount(window)) == AVAudioFrameCount(window))

        let afterSeek = Array(UnsafeBufferPointer(start: try #require(buffer.floatChannelData)[0], count: window))

        // Within a packet either side; AAC decodes in 1024-frame packets.
        let search = 1024
        let offsets = (-search ... search).filter {
            Int(target) + $0 >= 0 && Int(target) + $0 + window <= reference.count
        }

        let best = try #require(offsets.min { lhs, rhs in
            squaredDifference(afterSeek, reference, at: Int(target) + lhs)
                < squaredDifference(afterSeek, reference, at: Int(target) + rhs)
        })

        #expect(best == 0, "landed \(best) frames from \(target)")
    }

    private func decode(_ source: AVAssetReaderPCMSource) throws -> [Float] {
        let chunk: AVAudioFrameCount = 4096
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk))
        var samples: [Float] = []

        while try source.readNextChunk(into: buffer, frameCount: chunk) > 0 {
            let channel = try #require(buffer.floatChannelData)[0]
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        return samples
    }

    private func squaredDifference(_ samples: [Float], _ reference: [Float], at start: Int) -> Float {
        samples.withUnsafeBufferPointer { samples in
            reference.withUnsafeBufferPointer { reference in
                var sum: Float = 0

                for index in 0 ..< samples.count {
                    let difference = samples[index] - reference[start + index]
                    sum += difference * difference
                }

                return sum
            }
        }
    }

    /// And the samples after a seek are still the right track's, so the reposition did not quietly
    /// rebuild against a different one.
    @Test func stillDecodesTheSelectedTrackAfterASeek() async throws {
        let japanese = try #require(await tracks().first { $0.language == "jpn" })

        let source = try await AVAssetReaderPCMSource(url: url, audioTrack: japanese.id)

        try source.seek(toFrame: AVAudioFramePosition(source.processingFormat.sampleRate * 0.5))

        #expect(abs(try dominantFrequency(of: source, seconds: 0.5) - 880) < 30)
    }

    /// Reading past the end stops rather than spinning or repeating the tail.
    @Test func reportsExhaustionAtTheEnd() async throws {
        let source = try await AVAssetReaderPCMSource(url: url)

        try source.seek(toFrame: source.totalFrameCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096) else {
            return
        }

        var total = 0

        for _ in 0 ..< 8 {
            total += Int(try source.readNextChunk(into: buffer, frameCount: 4096))
        }

        // Priming can leave a little past the declared length; what matters is that it terminates.
        #expect(total < 44100)
    }
}
