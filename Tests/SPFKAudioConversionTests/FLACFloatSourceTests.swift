// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// A float source reaches the FLAC encoder through every edit render and through a float WAV or
/// AIFF conversion; its samples must arrive at their own level, not as silence.
@Suite(.tags(.file))
class FLACFloatSourceTests: BinTestCase {
    private func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: buffer)
        let data = try #require(buffer.floatChannelData)
        return (0 ..< Int(buffer.frameLength)).map { data[0][$0] }
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    @Test func floatWAVConvertsToFLACWithoutLoss() async throws {
        let sampleRate: Double = 44100
        let values: [Float] = (0 ..< 4410).map { 0.5 * sin(Float($0) * 2 * .pi * 440 / Float(sampleRate)) }

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
        buffer.frameLength = AVAudioFrameCount(values.count)
        let channel = try #require(buffer.floatChannelData)
        for (i, value) in values.enumerated() { channel[0][i] = value }

        let input = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)
        do {
            let file = try AVAudioFile(forWriting: input, settings: format.settings)
            try file.write(from: buffer)
        }

        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)
        let source = AudioFormatConverterSource(
            input: input,
            output: output,
            options: AudioFormatConverterOptions(),
            metadataCopyScheme: .ignore
        )
        try await AudioFormatConverter(source: source).start()

        let decoded = try samples(of: output)
        #expect(decoded.count == values.count)

        let maxError = zip(values, decoded).reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        // A 24-bit quantization step.
        #expect(maxError < 1.0 / 8_388_608 * 2, "peak \(peak(decoded)) against \(peak(values))")
    }

    @Test func trimmedFLACRenderKeepsItsLevel() async throws {
        let source = TestBundleResources.shared.tabla_flac
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 2.0)),
            outputURL: output
        )
        try await renderer.render()

        let sourceFile = try AVAudioFile(forReading: source)
        let sampleRate = sourceFile.processingFormat.sampleRate
        let all = try samples(of: source)
        let window = Array(all[Int(0.5 * sampleRate) ..< min(all.count, Int(2.0 * sampleRate))])

        let rendered = peak(try samples(of: output))
        let expected = peak(window)

        #expect(expected > 0.1)
        // Within 1 dB of the source window.
        #expect(abs(20 * log10(rendered / expected)) < 1, "rendered peak \(rendered), source window peak \(expected)")
    }
}
