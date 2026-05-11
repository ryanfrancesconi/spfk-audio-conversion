// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class AudioEditRendererTests: BinTestCase {
    // MARK: - Helpers

    /// Build a mono WAV file from sample values and return its URL.
    private func makeTempWAV(
        samples: [Float],
        sampleRate: Double = 44100,
        name: String = UUID().uuidString
    ) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, s) in samples.enumerated() {
            buffer.floatChannelData![0][i] = s
        }
        let url = bin.appending(component: "\(name).wav", directoryHint: .notDirectory)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { return [] }
        return (0 ..< Int(buffer.frameLength)).map { data[0][$0] }
    }

    // MARK: - render()

    @Test func renderTrimReducesFrameLength() async throws {
        // 10 frames at 44100 Hz. Trim 2 frames from head and 3 from tail → 5 frames remain.
        let sampleRate: Double = 44100
        let source = try makeTempWAV(
            samples: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            sampleRate: sampleRate,
            name: "render_trim_src"
        )
        let output = bin.appending(component: "render_trim_out.wav", directoryHint: .notDirectory)
        // Derive trim times from exact frame counts to avoid floating-point rounding
        let trimStart = 2.0 / sampleRate
        let trimEnd = 3.0 / sampleRate
        let edit = AudioEditDescription(trimStart: trimStart, trimEnd: trimEnd)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore
        )
        try await renderer.render()

        let result = try AVAudioFile(forReading: output)
        #expect(result.length == 5)

        let out = try readSamples(from: output)
        #expect(out == [2, 3, 4, 5, 6])
    }

    @Test func renderReverseFlipsContent() async throws {
        let source = try makeTempWAV(
            samples: [1, 2, 3, 4, 5],
            sampleRate: 44100,
            name: "render_reverse_src"
        )
        let output = bin.appending(component: "render_reverse_out.wav", directoryHint: .notDirectory)
        let edit = AudioEditDescription(isReversed: true)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore
        )
        try await renderer.render()

        let out = try readSamples(from: output)
        #expect(out[0] == 5)
        #expect(out[4] == 1)
    }

    @Test func renderFadeInFirstSampleNearZero() async throws {
        let sampleRate: Double = 44100
        let fadeInSamples = Int(sampleRate * 0.1)
        let samples = Array(repeating: Float(1.0), count: fadeInSamples * 2)

        let source = try makeTempWAV(
            samples: samples,
            sampleRate: sampleRate,
            name: "render_fadein_src"
        )
        let output = bin.appending(component: "render_fadein_out.wav", directoryHint: .notDirectory)
        let edit = AudioEditDescription(fadeIn: 0.1)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore
        )
        try await renderer.render()

        let out = try readSamples(from: output)
        #expect(out[0] < 0.1, "first sample should be near 0 for a fade-in")
        #expect(out[fadeInSamples - 1] > 0.9, "last fade-in sample should be near 1")
    }

    @Test func renderPreservesFormatSettings() async throws {
        // Source is 44100 Hz mono — output should preserve sample rate and channel count.
        let source = try makeTempWAV(
            samples: [Float](repeating: 0.5, count: 1000),
            sampleRate: 44100,
            name: "render_format_src"
        )
        let output = bin.appending(component: "render_format_out.wav", directoryHint: .notDirectory)
        let edit = AudioEditDescription(fadeIn: 0.01)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore
        )
        try await renderer.render()

        let resultFile = try AVAudioFile(forReading: output)
        #expect(resultFile.fileFormat.sampleRate == 44100)
        #expect(resultFile.fileFormat.channelCount == 1)
    }

    @Test func renderThrowsOnConflictWithErrorScheme() async throws {
        let source = try makeTempWAV(
            samples: [0.1, 0.2, 0.3],
            sampleRate: 44100,
            name: "render_conflict_src"
        )
        // Write a file at the output path first so it already exists.
        let output = try makeTempWAV(
            samples: [0.0],
            sampleRate: 44100,
            name: "render_conflict_out"
        )
        let edit = AudioEditDescription(fadeIn: 0.1)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore,
            fileConflictScheme: .error
        )

        await #expect(throws: (any Error).self) {
            try await renderer.render()
        }
    }

    @Test func renderOverwriteSchemeReplacesFile() async throws {
        let source = try makeTempWAV(
            samples: [Float](repeating: 0.5, count: 100),
            sampleRate: 44100,
            name: "render_overwrite_src"
        )
        let output = try makeTempWAV(
            samples: [0.0],
            sampleRate: 44100,
            name: "render_overwrite_out"
        )
        let edit = AudioEditDescription(fadeIn: 0.001)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore,
            fileConflictScheme: .overwrite
        )

        // Should not throw
        let resultURL = try await renderer.render()
        let result = try AVAudioFile(forReading: resultURL)
        #expect(result.length == 100)
    }

    @Test func renderUniqueSchemeDoesNotThrowOnConflict() async throws {
        let source = try makeTempWAV(
            samples: [Float](repeating: 0.5, count: 100),
            sampleRate: 44100,
            name: "render_unique_src"
        )
        let output = try makeTempWAV(
            samples: [0.0],
            sampleRate: 44100,
            name: "render_unique_out"
        )

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(fadeIn: 0.001),
            outputURL: output,
            metadataCopyScheme: .ignore,
            fileConflictScheme: .unique
        )

        let resultURL = try await renderer.render()
        // The returned URL must be different from the original (a new unique path was chosen)
        #expect(resultURL != output)
        #expect(resultURL.exists)
    }

    @Test func renderTrimThenReversePreservesPipelineOrder() async throws {
        // 5 frames at 44100 Hz. Trim 1 frame from head, reverse → [5, 4, 3, 2].
        let sampleRate: Double = 44100
        let source = try makeTempWAV(
            samples: [1, 2, 3, 4, 5],
            sampleRate: sampleRate,
            name: "render_trim_reverse_src"
        )
        let output = bin.appending(
            component: "render_trim_reverse_out.wav",
            directoryHint: .notDirectory
        )
        let edit = AudioEditDescription(trimStart: 1.0 / sampleRate, isReversed: true)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            metadataCopyScheme: .ignore
        )
        try await renderer.render()

        let out = try readSamples(from: output)
        #expect(out == [5, 4, 3, 2])
    }
}
