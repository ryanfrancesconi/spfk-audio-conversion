// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

/// The audio half of MXF support: `AVAudioFile` refuses the container, so everything ShadowTag does
/// with an MXF's audio comes through this source.
///
/// Gated on the plug-ins being installed — Apple ships MXF support as a separate download, so on a
/// machine without it there is nothing to read.
@Suite(.tags(.file), .serialized)
struct AVAssetReaderPCMSourceMXFTests {
    private var url: URL { TestBundleResources.shared.sample_mxf }

    @Test("AVAudioFile cannot open the same file", .enabled(if: ProVideoFormats.isAvailable))
    func avAudioFileRefusesMXF() {
        #expect(throws: (any Error).self) {
            try AVAudioFile(forReading: url)
        }
    }

    /// **Read the fixture's own rate off the source rather than hardcoding it**, and check that
    /// samples actually came out: a wrong ASBD decodes silence while reporting success at every
    /// step, so a frame count on its own would not tell the difference.
    @Test("Decodes real samples", .enabled(if: ProVideoFormats.isAvailable))
    func decodesRealSamples() async throws {
        let source = try await AVAssetReaderPCMSource(url: url)

        #expect(source.processingFormat.sampleRate > 0)
        #expect(source.processingFormat.channelCount > 0)
        #expect(source.totalFrameCount > 0)

        let wanted = AVAudioFrameCount(source.processingFormat.sampleRate * 0.5)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: wanted))

        var read: AVAudioFrameCount = 0
        var peak: Float = 0

        while read < wanted {
            let written = try source.readNextChunk(into: buffer, frameCount: wanted)

            guard written > 0, let data = buffer.floatChannelData else { break }

            for index in 0 ..< Int(written) {
                peak = max(peak, abs(data[0][index]))
            }

            read += written
        }

        #expect(read > 0)
        #expect(peak > 0.01, "decoded \(read) frames of silence")
    }

    /// The whole file, to the end, with no short read or stall — the shape a waveform scan takes.
    @Test("Scans to the declared end", .enabled(if: ProVideoFormats.isAvailable))
    func scansToEnd() async throws {
        let source = try await AVAssetReaderPCMSource(url: url)
        let chunk = AVAudioFrameCount(4096)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk))

        var total: AVAudioFramePosition = 0

        while true {
            let written = try source.readNextChunk(into: buffer, frameCount: chunk)

            guard written > 0 else { break }

            total += AVAudioFramePosition(written)
        }

        #expect(total == source.totalFrameCount)
    }
}
