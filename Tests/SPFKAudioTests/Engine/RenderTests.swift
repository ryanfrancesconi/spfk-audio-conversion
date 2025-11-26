// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.engine))
final class RenderTests: AudioPlayerTestCase {
    @Test(arguments: [pcmFormatFloat32, pcmFormatInt24])
    func render(format: [String: Any]) async throws {
        deleteBinOnExit = true
        try await setup()
        guard let player else { return }

        try player.load(url: TestBundleResources.shared.tabla_wav)
        let audioFile = try createFile(name: #function, settings: format)
        try await render(player: player, to: audioFile, duration: 2, renderUntilSilent: false)

        Log.debug("rendered duration is", audioFile.duration)

        #expect(audioFile.duration == 2)
    }

    @Test(arguments: [pcmFormatFloat32, pcmFormatInt24])
    func renderUntilSilent(format: [String: Any]) async throws {
        deleteBinOnExit = true
        try await setup()
        guard let player else { return }

        try player.load(url: TestBundleResources.shared.tabla_wav)
        let audioFile = try createFile(name: #function, settings: format)
        try await render(player: player, to: audioFile, duration: 2, renderUntilSilent: true)

        Log.debug("rendered duration is", audioFile.duration)

        #expect(audioFile.duration.isApproximatelyEqual(to: 2.39, absoluteTolerance: 0.01))
    }

    @Test(arguments: [pcmFormatFloat32])
    func renderCancel(format: [String: Any]) async throws {
        deleteBinOnExit = true
        try await setup()
        guard let player else { return }

        try player.load(url: TestBundleResources.shared.tabla_wav)
        let audioFile = try createFile(name: #function, settings: format)

        Task {
            try await Task.sleep(seconds: 0.01)
            await self.audioWorkspace.engineManager.renderer?.cancel()
        }

        try await render(player: player, to: audioFile, duration: 120, renderUntilSilent: true)

        Log.debug("rendered duration is", audioFile.duration)

        #expect(!audioFile.url.exists)
    }
}

extension RenderTests {
    static var pcmFormatFloat32: [String: Any] {
        let sampleRate = 48000.0
        let channels = 2

        let formatSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, // Use integer samples for WAV
            AVLinearPCMIsBigEndianKey: false, // Use little-endian (common for WAV)
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            "name": "pcmFormatFloat32_48k",
        ]

        return formatSettings
    }

    static var pcmFormatInt24: [String: Any] {
        let sampleRate = 48000.0
        let channels = 2

        let formatSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false, // Use integer samples for WAV
            AVLinearPCMIsBigEndianKey: false, // Use little-endian (common for WAV)
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            "name": "pcmFormatInt24_48k",
        ]

        return formatSettings
    }

    func createFile(name: String, settings format: [String: Any]) throws -> AVAudioFile {
        let filename = "\(name)_\(format["name"] ?? "?").wav"
        let url = bin.appendingPathComponent(filename)
        let audioFile = try AVAudioFile(forWriting: url, settings: format)
        return audioFile
    }

    private func render(player: FilePlayer, to audioFile: AVAudioFile, duration: TimeInterval, renderUntilSilent: Bool) async throws {
        let prerender = {
            try player.schedule() // (from: 0, to: 2, when: 0)
            try player.play()
        }

        let postrender = {
            player.stop()
        }

        #expect(audioFile.duration == 0)

        try await audioWorkspace.engineManager.render(
            to: audioFile,
            duration: duration,
            options: .init(renderUntilSilent: renderUntilSilent),
            prerender: prerender,
            postrender: postrender,
            progressHandler: { progress in
                // Log.debug(progress)
            }
        )
    }
}
