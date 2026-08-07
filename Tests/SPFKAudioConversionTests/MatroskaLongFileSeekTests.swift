// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKBase
import SPFKMatroska
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// Seek latency against a real feature-length file.
///
/// Bundled fixtures are seconds long, and every defect in this area has been a length assumption
/// that seconds cannot express. The file is named by `SPFK_LONG_MEDIA` rather than committed, so
/// this suite is skipped everywhere it is not deliberately pointed at one.
///
///     SPFK_LONG_MEDIA="/path/to/two-hour.mkv" xcodebuild … test
@Suite(.tags(.file), .serialized, .enabled(if: LongMediaFixture.url != nil))
struct MatroskaLongFileSeekTests {
    /// Seeks to time. A scrubber that takes longer than this is the complaint, not a measurement.
    static let seekBudget: Duration = .milliseconds(250)

    @Test func reportsFileShape() throws {
        let url = try #require(LongMediaFixture.url)
        let decoder = try MatroskaAudioDecoder(url: url)

        let duration = try #require(decoder.file.duration)

        Log.debug("""
        📏 \(url.lastPathComponent)
           duration \(duration)s  rate \(decoder.processingFormat.sampleRate)  \
        channels \(decoder.processingFormat.channelCount)  codec \(decoder.track.codecID)
        """)

        #expect(duration > 600, "not a long file — this suite measures nothing")
    }

    /// The operation a scrubber performs. Random rather than swept, so an unlucky region cannot be
    /// mistaken for the general case.
    @Test func seeksToRandomPositionsWithinBudget() throws {
        let url = try #require(LongMediaFixture.url)
        let decoder = try MatroskaAudioDecoder(url: url)

        let duration = try #require(decoder.file.duration)
        let rate = decoder.processingFormat.sampleRate

        var generator = SeededGenerator(seed: 20_260_807)
        let targets = (0 ..< 12).map { _ in TimeInterval.random(in: 0 ... duration, using: &generator) }

        var samples: [(TimeInterval, Duration)] = []

        for target in targets {
            let frame = AVAudioFramePosition(target * rate)

            let clock = ContinuousClock()
            let elapsed = try clock.measure {
                try decoder.seek(toFrame: frame)
            }

            samples.append((target, elapsed))

            // The landing has to be exact, not merely fast — a cheap seek to the wrong place is a
            // worse answer than a slow one.
            #expect(decoder.framePosition == frame, "landed at \(decoder.framePosition), asked for \(frame)")
        }

        for (target, elapsed) in samples.sorted(by: { $0.1 < $1.1 }) {
            Log.debug("⏱ seek to \(Int(target))s took \(elapsed)")
        }

        let worst = try #require(samples.map(\.1).max())

        #expect(worst <= Self.seekBudget, "slowest seek was \(worst)")
    }

    /// Seeking backward is the case a container without an index cannot do cheaply. This file has
    /// `Cues`, so it must not behave like one.
    @Test func seeksBackwardAsCheaplyAsForward() throws {
        let url = try #require(LongMediaFixture.url)
        let decoder = try MatroskaAudioDecoder(url: url)

        let duration = try #require(decoder.file.duration)
        let rate = decoder.processingFormat.sampleRate

        let clock = ContinuousClock()

        try decoder.seek(toFrame: AVAudioFramePosition(duration * 0.9 * rate))

        let backward = try clock.measure {
            try decoder.seek(toFrame: AVAudioFramePosition(duration * 0.1 * rate))
        }

        let forward = try clock.measure {
            try decoder.seek(toFrame: AVAudioFramePosition(duration * 0.2 * rate))
        }

        Log.debug("⏱ backward \(backward)  forward \(forward)")

        #expect(backward <= Self.seekBudget, "backward seek took \(backward)")
        #expect(forward <= Self.seekBudget, "forward seek took \(forward)")
    }

    /// What playback actually does: read chunk after chunk for a long stretch. A per-read cost that
    /// grows with position would not show up in a seek measurement at all.
    @Test func sustainedReadingDoesNotSlowDown() throws {
        let url = try #require(LongMediaFixture.url)
        let decoder = try MatroskaAudioDecoder(url: url)

        let format = decoder.processingFormat
        let chunk: AVAudioFrameCount = 8192

        func readCost(from seconds: TimeInterval, reads: Int) throws -> Duration {
            try decoder.seek(toFrame: AVAudioFramePosition(seconds * format.sampleRate))

            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk))

            return try ContinuousClock().measure {
                for _ in 0 ..< reads {
                    _ = try decoder.readNextChunk(into: buffer, frameCount: chunk)
                }
            }
        }

        let early = try readCost(from: 60, reads: 200)
        let late = try readCost(from: 7000, reads: 200)

        Log.debug("⏱ 200 reads at 60s \(early)  at 7000s \(late)")

        // Same work either way, so a large divergence means position is costing something.
        #expect(late < early * 3, "reading late in the file cost \(late) against \(early) early")
    }
}

/// The file under test, or `nil` when none was named.
enum LongMediaFixture {
    static var url: URL? {
        guard let path = ProcessInfo.processInfo.environment["SPFK_LONG_MEDIA"], path.isEmpty == false else {
            return nil
        }

        let url = URL(fileURLWithPath: path)

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Reproducible targets, so a slow seek can be looked at again.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Splits the seek into its two halves, because the total says nothing about which is slow.
@Suite(.tags(.file), .serialized, .enabled(if: LongMediaFixture.url != nil))
struct MatroskaLongFileSeekBreakdownTests {
    @Test func attributesSeekCostToIndexLookupOrDiscard() throws {
        let url = try #require(LongMediaFixture.url)

        let decoder = try MatroskaAudioDecoder(url: url)
        let duration = try #require(decoder.file.duration)
        let rate = decoder.processingFormat.sampleRate
        let track = decoder.track

        let clock = ContinuousClock()

        for fraction in [0.1, 0.35, 0.6, 0.85] {
            let target = duration * fraction

            // The container half, measured on its own reader so the decoder's state is untouched.
            let reader = try MatroskaFrameReader(url: url)

            let lookup = try clock.measure {
                try reader.seek(to: max(0, target - 0.5), trackNumber: track.number)
            }

            // How far before the target the index actually landed — this is what has to be decoded
            // and thrown away.
            let firstFrame = try reader.nextFrame()
            let landed = firstFrame?.timestamp ?? 0

            // The decode half, through the real decoder.
            let whole = try clock.measure {
                try decoder.seek(toFrame: AVAudioFramePosition(target * rate))
            }

            print("""
            ⏱ target \(Int(target))s | index lookup \(lookup) | landed at \(String(format: "%.2f", landed))s \
            (\(String(format: "%.2f", target - landed))s to discard) | whole seek \(whole)
            """)
        }
    }
}
