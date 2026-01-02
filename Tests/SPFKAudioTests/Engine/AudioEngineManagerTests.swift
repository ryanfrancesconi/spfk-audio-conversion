// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudio
import SPFKBase
import SPFKTesting
import Testing

@Suite(.serialized, .tags(.engine))
final class AudioEngineManagerTests: TestCaseModel, @unchecked Sendable {
    lazy var engineManager: AudioEngineManager? = AudioEngineManager(delegate: self)

    @Test func state() async throws {
        let engineManager = engineManager!

        await engineManager.rebuildEngine()

        try engineManager.startEngine()

        #expect(engineManager.engineIsRunning)

        Log.debug(engineManager.debugDescription)

        await engineManager.rebuildEngine()
        #expect(!engineManager.engineIsRunning)

        try engineManager.startEngine()
        #expect(engineManager.engineIsRunning)

        engineManager.stopEngine()

        self.engineManager = nil
        // try await wait(sec: 4)
    }

    @Test func connectAndAttach() async throws {
        // try await wait(sec: 4)

        guard let engineManager, let outputNode = engineManager.outputNode else { return }
        await engineManager.rebuildEngine()

        var fader: Fader? = try await Fader()

        try await engineManager.connectAndAttach(fader!.avAudioNode, to: outputNode)

        fader = nil

        // try await wait(sec: 4)
    }
}

extension AudioEngineManagerTests: AudioEngineManagerDelegate {
    func audioEngineManagerAllowInputDevice() -> Bool {
        true
    }

    func audioEngineManager(event: SPFKAudio.AudioEngineManager.Event) {
        Log.debug(event)
    }
}
