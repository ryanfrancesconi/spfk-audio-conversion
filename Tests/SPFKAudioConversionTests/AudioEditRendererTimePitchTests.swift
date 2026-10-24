// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMatroska
import SPFKTempo
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// The stretch inside the render: its length, its context, and that it produced audio.
@Suite(.tags(.file))
class AudioEditRendererTimePitchTests: BinTestCase {
    static let edits: [(name: String, timePitch: TimePitchDescription)] = [
        ("0.5x", TimePitchDescription(rate: 0.5)),
        ("1.5x", TimePitchDescription(rate: 1.5)),
        ("+7st", TimePitchDescription(semitones: 7)),
    ]

    static let formats: [URL] = [
        TestBundleResources.shared.tabla_wav,
        TestBundleResources.shared.tabla_aif,
        TestBundleResources.shared.tabla_m4a,
        TestBundleResources.shared.tabla_mp3,
        TestBundleResources.shared.tabla_flac,
    ]

    private func edit(_ timePitch: TimePitchDescription) -> AudioEditDescription {
        var edit = AudioEditDescription(trim: TrimDescription(inPoint: 1, outPoint: 3))
        edit.timePitch = timePitch
        return edit
    }

    @Test(arguments: formats)
    func everyFormatRendersToTheExactLength(source: URL) async throws {
        for (name, timePitch) in Self.edits {
            let output = bin.appending(component: "\(name)-\(source.lastPathComponent)")
            let renderer = AudioEditRenderer(sourceURL: source, edit: edit(timePitch), outputURL: output)

            let probe = try await renderer.probeAudioFile()

            #expect(probe.processedFrames == timePitch.outputFrameCount(forInput: probe.materialFrames), "\(name) \(source.lastPathComponent)")
            #expect(probe.peak > 0.01, "\(name) \(source.lastPathComponent): no audio came out")

            try await renderer.render()

            // Encoder priming moves a lossy file's decoded length, so only lossless files are held
            // to it on disk.
            if [.wav, .aiff, .flac].contains(AudioFileType(pathExtension: source.pathExtension)) {
                let written = try AVAudioFile(forReading: output)
                #expect(Int(written.length) == probe.processedFrames, "\(name) \(source.lastPathComponent) on disk")
            }
        }
    }

    /// The trim window read with its context renders bit-identically to the stretcher handed the
    /// whole file, so the context reaches every analysis window the material needs.
    @Test(arguments: [0.5, 1.5, 2.0])
    func theWindowsContextIsAllTheStretcherNeeds(rate: Double) async throws {
        let source = TestBundleResources.shared.tabla_wav
        let renderer = AudioEditRenderer(sourceURL: source, edit: edit(TimePitchDescription(rate: rate)), outputURL: bin.appending(component: "x.wav"))

        let comparison = try await renderer.compareStretchWithWholeFile(material: 1 ... 3)

        #expect(comparison.contextBefore > 0 && comparison.contextAfter > 0)
        #expect(comparison.frames == comparison.expectedFrames)
        #expect(comparison.maxDifference == 0)
    }

    /// The decoder route reads its own context.
    @Test func theDecoderRouteReadsTheSameContext() async throws {
        let source = TestBundleResources.shared.tabla_pcm_mka
        let timePitch = TimePitchDescription(rate: 0.75)
        let renderer = AudioEditRenderer(sourceURL: source, edit: edit(timePitch), outputURL: bin.appending(component: "mka.wav"))

        let probe = try await renderer.probeMatroska()

        let needed = try TimePitchRenderer.contextFrames(
            for: timePitch, sampleRate: probe.sampleRate, channelCount: probe.channelCount, quality: .best
        )

        #expect(probe.contextBefore == min(needed.pre, Int(1 * probe.sampleRate)))
        #expect(probe.contextAfter == needed.post)
        #expect(probe.materialFrames == Int(2 * probe.sampleRate))
        #expect(probe.processedFrames == timePitch.outputFrameCount(forInput: probe.materialFrames))
        #expect(probe.peak > 0.01)
    }

    /// Context that the file does not have is not invented: a window at the file's start has none
    /// before it.
    @Test func noContextIsReadBeyondTheFile() async throws {
        let source = TestBundleResources.shared.tabla_wav
        var edit = AudioEditDescription()
        edit.timePitch = TimePitchDescription(rate: 2)
        let renderer = AudioEditRenderer(sourceURL: source, edit: edit, outputURL: bin.appending(component: "whole.wav"))

        let probe = try await renderer.probeAudioFile()

        #expect(probe.contextBefore == 0)
        #expect(probe.contextAfter == 0)
        #expect(Int64(probe.materialFrames) == (try AVAudioFile(forReading: source)).length)
    }

    @Test func aPitchOnlyRenderKeepsItsLength() async throws {
        let source = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "pitch.wav")
        var edit = AudioEditDescription()
        edit.timePitch = TimePitchDescription(semitones: -3, cents: 20)

        try await AudioEditRenderer(sourceURL: source, edit: edit, outputURL: output).render()

        #expect(try AVAudioFile(forReading: output).length == AVAudioFile(forReading: source).length)
    }

    /// One source second of fade is half a second of output at 2x: the render matches the unfaded
    /// one from there on, and is quieter before it.
    @Test func fadesCoverTheSameMaterialAfterTheStretch() async throws {
        let source = TestBundleResources.shared.tabla_wav

        func render(fadeIn: TimeInterval) async throws -> WindowProbe {
            var edit = AudioEditDescription()
            edit.fade.inTime = fadeIn
            edit.timePitch = TimePitchDescription(rate: 2)

            let renderer = AudioEditRenderer(sourceURL: source, edit: edit, outputURL: bin.appending(component: "fade\(fadeIn).wav"))
            return try await renderer.probeAudioFile()
        }

        let faded = try await render(fadeIn: 1)
        let plain = try await render(fadeIn: 0)
        let fadeEnd = Int(0.5 * faded.sampleRate)

        let x = faded.firstChannel, y = plain.firstChannel
        #expect(x.count == y.count)

        var differsAfter = false, differsBefore = false
        for i in fadeEnd ..< min(x.count, y.count) where x[i] != y[i] { differsAfter = true }
        for i in 0 ..< fadeEnd where x[i] != y[i] { differsBefore = true }

        #expect(!differsAfter)
        #expect(differsBefore)
    }

}

/// What a test reads off a render's internals, made inside the actor.
struct WindowProbe: Sendable {
    var sampleRate: Double
    var channelCount: Int
    var materialFrames: Int
    var contextBefore: Int
    var contextAfter: Int
    var processedFrames: Int
    var peak: Float
    var firstChannel: [Float]
}

extension AudioEditRenderer {
    func probeAudioFile() async throws -> WindowProbe {
        let file = try AVAudioFile(forReading: sourceURL)
        return try await probe(readWindow(from: file), fileFormat: file.fileFormat)
    }

    func probeMatroska() async throws -> WindowProbe {
        let decoder = try MatroskaAudioDecoder(url: sourceURL, audioTrack: nil)
        return try await probe(readWindow(from: decoder), fileFormat: decoder.processingFormat)
    }

    private func probe(_ window: RenderWindow, fileFormat: AVAudioFormat) async throws -> WindowProbe {
        let processed = try await processEdit(window, fileFormat: fileFormat, writingTo: outputURL)
        let first = processed.floatChannelData.map { Array(UnsafeBufferPointer(start: $0[0], count: Int(processed.frameLength))) } ?? []

        return WindowProbe(
            sampleRate: window.buffer.format.sampleRate,
            channelCount: Int(window.buffer.format.channelCount),
            materialFrames: Int(window.buffer.frameLength) - window.contextBefore - window.contextAfter,
            contextBefore: window.contextBefore,
            contextAfter: window.contextAfter,
            processedFrames: Int(processed.frameLength),
            peak: try processed.peak().amplitude,
            firstChannel: first
        )
    }

    /// The windowed stretch against the stretcher handed the whole file with `material` seconds
    /// marked as material.
    func compareStretchWithWholeFile(
        material seconds: ClosedRange<Double>
    ) async throws -> (contextBefore: Int, contextAfter: Int, frames: Int, expectedFrames: Int, maxDifference: Float) {
        let window = try await readWindow(from: AVAudioFile(forReading: sourceURL))
        let stretched = try await stretched(window)

        let file = try AVAudioFile(forReading: sourceURL)
        guard let whole = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(description: "allocation")
        }
        try file.read(into: whole)

        let sampleRate = file.processingFormat.sampleRate
        nonisolated(unsafe) let input = whole
        let expected = try await TimePitchRenderer.render(
            input,
            material: Int(seconds.lowerBound * sampleRate) ..< Int(seconds.upperBound * sampleRate),
            description: edit.timePitch,
            quality: renderSettings.timePitchQuality
        )

        var worst: Float = 0
        if let x = stretched.floatChannelData, let y = expected.floatChannelData {
            for channel in 0 ..< Int(stretched.format.channelCount) {
                for i in 0 ..< Int(min(stretched.frameLength, expected.frameLength)) {
                    worst = max(worst, abs(x[channel][i] - y[channel][i]))
                }
            }
        } else {
            worst = .infinity
        }

        return (window.contextBefore, window.contextAfter, Int(stretched.frameLength), Int(expected.frameLength), worst)
    }
}
