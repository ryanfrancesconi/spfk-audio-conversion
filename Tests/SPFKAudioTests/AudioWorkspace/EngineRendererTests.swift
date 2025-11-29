// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.engine))
final class EngineRendererTests: AudioPlayerTestCase {
    @Test(arguments: [pcmFormatFloat32, pcmFormatInt24])
    func render(format: [String: Any]) async throws {
        deleteBinOnExit = false
        try await setup()
        guard let player else { return }

        try player.load(url: TestBundleResources.shared.tabla_wav)
        let url = try createFile(name: #function, settings: format)
        let audioFile = try await render(player: player, to: url, settings: format, duration: 2, renderUntilSilent: false)

        Log.debug("rendered duration is", audioFile.duration)

        #expect(audioFile.duration == 2)
    }

    @Test(arguments: [pcmFormatFloat32, pcmFormatInt24])
    func renderUntilSilent(format: [String: Any]) async throws {
        deleteBinOnExit = false
        try await setup()
        guard let player else { return }
        try player.load(url: TestBundleResources.shared.tabla_wav)
        let url = try createFile(name: #function, settings: format)
        let audioFile = try await render(player: player, to: url, settings: format, duration: 2, renderUntilSilent: true)

        Log.debug("rendered duration is", audioFile.duration)

        #expect(audioFile.duration.isApproximatelyEqual(to: 2.3, absoluteTolerance: 0.1))
    }

    @Test(arguments: [pcmFormatFloat32, pcmFormatInt24])
    func renderUntilSilentWithEffects(format: [String: Any]) async throws {
        deleteBinOnExit = false
        try await setup()
        let audioUnitChain = try #require(audioUnitChain)
        let player = try #require(player)
        try await audioUnitChain.insertAudioUnit(componentDescription: auDelayDesc, at: 0)
        try await audioUnitChain.connect()
        try player.load(url: TestBundleResources.shared.tabla_wav)
        let url = try createFile(name: #function, settings: format)
        let audioFile = try await render(player: player, to: url, settings: format, duration: 2, renderUntilSilent: true)

        Log.debug("rendered duration is", audioFile.duration)

        #expect(audioFile.duration.isApproximatelyEqual(to: 12.288, absoluteTolerance: 0.1))
    }

    @Test(arguments: [pcmFormatFloat32, pcmFormatInt24])
    func renderCancel(format: [String: Any]) async throws {
        deleteBinOnExit = false
        try await setup()
        guard let player else { return }

        try player.load(url: TestBundleResources.shared.tabla_wav)
        let url = try createFile(name: #function, settings: format)

        Task {
            try await Task.sleep(seconds: 0.001)
            await self.audioWorkspace.engineManager.renderer.cancelRender()
        }

        await #expect(throws: CancellationError.self) {
            try await render(player: player, to: url, settings: format, duration: 120, renderUntilSilent: true)
        }
    }
}

extension EngineRendererTests {
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

    func createFile(name: String, settings format: [String: Any]) throws -> URL {
        let filename = "\(name)_\(format["name"] ?? "?").wav"
        return bin.appendingPathComponent(filename)
    }

    private func render(player: FilePlayer, to url: URL, settings: [String: Any], duration: TimeInterval, renderUntilSilent: Bool) async throws -> AVAudioFile {
        let prerender = { @Sendable in
            try player.schedule(from: 0, to: 2, when: 0)
            try player.play()
        }

        let postrender = { @Sendable in
            player.stop()
        }

        try await audioWorkspace.engineManager.render(
            to: url,
            settings: settings,
            duration: duration,
            options: .init(renderUntilSilent: renderUntilSilent),
            prerender: prerender,
            postrender: postrender,
            progressHandler: { progress in
                Log.debug(progress)
            },
            disableManualRenderingModeOnCompletion: true
        )

        guard let audioFile = await audioWorkspace.engineManager.renderer.audioFile else {
            throw NSError(description: "audioFile is nil")
        }

        return audioFile
    }
}
