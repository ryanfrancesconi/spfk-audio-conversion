// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// A reversed render: the trimmed window played backwards, stretched after the reversal, with its
/// markers mirrored onto the rendered timeline.
@Suite(.tags(.file, .reverse), .serialized)
final class ReversedRenderTests: BinTestCase {
    private static let sources: [URL] = [
        TestBundleResources.shared.tabla_wav,
        TestBundleResources.shared.tabla_aif,
        TestBundleResources.shared.tabla_m4a,
        TestBundleResources.shared.tabla_mp3,
        TestBundleResources.shared.tabla_flac,
    ]

    private static let trim = TrimDescription(inPoint: 0.5, outPoint: 3.5)
    private static let markerTimes: [TimeInterval] = [1, 1.75]

    private func readAll(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let data = try #require(buffer.floatChannelData)
        let channels = (0 ..< Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: Int(buffer.frameLength))) }
        return (channels, file.processingFormat.sampleRate)
    }

    private func render(_ source: URL, rate: Double) async throws -> URL {
        deleteBinOnExit = true
        let type = try #require(AudioFileType(pathExtension: source.pathExtension))
        let input = bin.appendingPathComponent("source.\(source.pathExtension)")
        try FileManager.default.copyItem(at: source, to: input)
        let markers = Self.markerTimes.enumerated().map { AudioMarkerDescription(name: "m\($0.offset)", startTime: $0.element) }
        #expect(AudioFormatConverter.writeMarkers(markers, to: input, outputType: type))

        var edit = AudioEditDescription(trim: Self.trim, isReversed: true)
        edit.timePitch.rate = rate

        let output = bin.appendingPathComponent("reversed.\(source.pathExtension)")
        return try await AudioEditRenderer(sourceURL: input, edit: edit, outputURL: output).render()
    }

    /// RMS over consecutive windows of `hop` frames, of channel 0.
    private func envelope(_ samples: ArraySlice<Float>, hop: Double) -> [Float] {
        let count = Int(Double(samples.count) / hop)
        return (0 ..< count).map { k in
            let start = samples.startIndex + Int(Double(k) * hop)
            let end = min(samples.endIndex, samples.startIndex + Int(Double(k + 1) * hop))
            let window = samples[start ..< end]
            return (window.reduce(0) { $0 + $1 * $1 } / Float(max(1, window.count))).squareRoot()
        }
    }

    /// The lag of `signal` against `reference` with the best normalized correlation, within `±maxLag`.
    private func bestLag(_ signal: [Float], _ reference: [Float], maxLag: Int) -> (lag: Int, correlation: Float) {
        var best = (lag: 0, correlation: -Float.infinity)
        for lag in -maxLag ... maxLag {
            var sum: Float = 0, a2: Float = 0, b2: Float = 0
            for i in 0 ..< reference.count {
                let j = i + lag
                guard signal.indices.contains(j) else { continue }
                sum += signal[j] * reference[i]
                a2 += signal[j] * signal[j]
                b2 += reference[i] * reference[i]
            }
            let correlation = sum / max(1e-9, (a2 * b2).squareRoot())
            if correlation > best.correlation { best = (lag, correlation) }
        }
        return best
    }

    @Test(arguments: sources)
    func reversedRenderPlaysTheWindowBackwards(source: URL) async throws {
        let output = try await render(source, rate: 1)
        let rendered = try readAll(output)
        let original = try readAll(source)
        let sampleRate = original.sampleRate

        let start = Int(Self.trim.inPoint * sampleRate)
        let end = Int(Self.trim.outPoint * sampleRate)
        let expected = Array(original.channels[0][start ..< end].reversed())
        let isLossy = [.mp3, .m4a].contains(AudioFileType(pathExtension: source.pathExtension))

        if isLossy {
            #expect(abs(rendered.channels[0].count - expected.count) < expected.count / 20)
            // An excerpt from the middle, searched near where it belongs.
            let excerpt = Array(expected[expected.count / 2 ..< expected.count / 2 + 8192])
            let tail = Array(rendered.channels[0].dropFirst(expected.count / 2))
            let found = bestLag(tail, excerpt, maxLag: 4096)
            print("reversed \(source.lastPathComponent): lag \(found.lag), correlation \(found.correlation)")
            #expect(found.correlation > 0.9)
        } else {
            #expect(rendered.channels[0].count == expected.count)
            // The 5 ms de-click at each trim edge aside, every sample is the source's, reversed.
            let margin = Int(0.006 * sampleRate)
            let worst = (margin ..< expected.count - margin).map { abs(rendered.channels[0][$0] - expected[$0]) }.max() ?? 0
            #expect(worst < 1e-4, "\(source.lastPathComponent): \(worst)")
        }

        try await expectMirroredMarkers(in: output, rate: 1)
    }

    @Test(arguments: sources)
    func reversedStretchFollowsTheReversedSource(source: URL) async throws {
        let rate = 1.5
        let output = try await render(source, rate: rate)
        let rendered = try readAll(output)
        let original = try readAll(source)
        let sampleRate = original.sampleRate

        let start = Int(Self.trim.inPoint * sampleRate)
        let end = Int(Self.trim.outPoint * sampleRate)
        let window = Array(original.channels[0][start ..< end].reversed())
        let expectedFrames = AudioEditDescription(timePitch: TimePitchDescription(rate: rate)).timePitch.outputFrameCount(forInput: window.count)

        #expect(abs(rendered.channels[0].count - expectedFrames) < expectedFrames / 20)

        // 10 ms of output covers 15 ms of source; the envelopes line up at lag 0.
        let hop = 0.01 * sampleRate
        let reference = envelope(window[...], hop: hop * rate)
        let heard = envelope(rendered.channels[0][...], hop: hop)
        let found = bestLag(heard, reference, maxLag: 20)
        print("stretched \(source.lastPathComponent): lag \(found.lag), correlation \(found.correlation)")
        #expect(abs(found.lag) <= 2, "\(source.lastPathComponent)")
        #expect(found.correlation > 0.8)

        try await expectMirroredMarkers(in: output, rate: rate)
    }

    /// Source markers at 1 and 1.75 s, trimmed to [0.5, 3.5], scaled by the rate and mirrored.
    private func expectMirroredMarkers(in output: URL, rate: Double) async throws {
        let duration = (Self.trim.outPoint - Self.trim.inPoint) / rate
        let expected = Self.markerTimes.map { duration - ($0 - Self.trim.inPoint) / rate }.sorted()
        let times = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions.map(\.startTime).sorted()

        #expect(times.count == expected.count, "\(output.lastPathComponent)")
        for (time, want) in zip(times, expected) {
            #expect(abs(time - want) < 0.02, "\(output.lastPathComponent): \(time) vs \(want)")
        }
    }
}
