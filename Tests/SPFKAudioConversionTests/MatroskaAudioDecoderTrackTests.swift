// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKMatroska
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

/// The Matroska half of per-track decoding — the same question `AVAssetReaderPCMSourceTests` asks of
/// the AVFoundation half, against a container AVFoundation will not open.
@Suite(.tags(.file), .serialized)
struct MatroskaAudioDecoderTrackTests {
    private var url: URL { TestBundleResources.shared.sample_dualaudio_mkv }

    /// 440 Hz and 880 Hz tone tracks, so the frequency names which one was decoded.
    private func dominantFrequency(of decoder: MatroskaAudioDecoder, seconds: Double = 1) throws -> Double {
        let wanted = AVAudioFrameCount(decoder.processingFormat.sampleRate * seconds)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: wanted) else {
            return 0
        }

        var samples: [Float] = []

        while samples.count < Int(wanted) {
            let written = try decoder.readNextChunk(into: buffer, frameCount: wanted)

            guard written > 0, let data = buffer.floatChannelData else { break }

            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(written)))
        }

        guard samples.count > 32 else { return 0 }

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

        return Double(crossings) / 2 / (Double(samples.count) / decoder.processingFormat.sampleRate)
    }

    private func trackIDs() throws -> (english: AudioTrackDescription.ID, japanese: AudioTrackDescription.ID) {
        let file = try MatroskaFile(url: url)
        let descriptions = file.audioTrackDescriptions

        let english = try #require(descriptions.first { $0.language == "eng" })
        let japanese = try #require(descriptions.first { $0.language == "jpn" })

        return (english.id, japanese.id)
    }

    /// A dual-audio film drew the waveform of whichever track the muxer wrote first, whatever the
    /// user had chosen.
    @Test func decodesTheTrackItWasAskedFor() throws {
        let ids = try trackIDs()

        let first = try MatroskaAudioDecoder(url: url, audioTrack: ids.english)
        let second = try MatroskaAudioDecoder(url: url, audioTrack: ids.japanese)

        #expect(abs(try dominantFrequency(of: first) - 440) < 15)
        #expect(abs(try dominantFrequency(of: second) - 880) < 25)
    }

    @Test func defaultsToTheFirstTrack() throws {
        #expect(abs(try dominantFrequency(of: MatroskaAudioDecoder(url: url)) - 440) < 15)
    }

    /// A stale selection still produces a waveform rather than throwing the file's load.
    @Test func fallsBackToTheFirstTrackForAnUnknownSelection() throws {
        let decoder = try MatroskaAudioDecoder(
            url: url,
            audioTrack: AudioTrackDescription.ID(rawValue: 999_999)
        )

        #expect(abs(try dominantFrequency(of: decoder) - 440) < 15)
    }

    /// Seeking must not silently rebuild against a different track — the reader is reopened to do
    /// it, which is exactly where a track choice could be dropped.
    @Test func keepsTheSelectedTrackAcrossASeek() throws {
        let decoder = try MatroskaAudioDecoder(url: url, audioTrack: try trackIDs().japanese)

        try decoder.seek(toFrame: AVAudioFramePosition(decoder.processingFormat.sampleRate * 0.5))

        #expect(abs(try dominantFrequency(of: decoder, seconds: 0.5) - 880) < 30)
    }
}
