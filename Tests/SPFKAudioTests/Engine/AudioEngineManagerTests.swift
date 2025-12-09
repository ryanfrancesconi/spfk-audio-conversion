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
        try await wait(sec: 4)

        if let engine = engineManager {
            try engine.startEngine()
            #expect(engine.engineIsRunning)

            Log.debug(engine.debugDescription)

            await engine.rebuildEngine()
            #expect(!engine.engineIsRunning)

            try engine.startEngine()
            #expect(engine.engineIsRunning)

            engine.stopEngine()
        }

        engineManager = nil
        try await wait(sec: 4)
    }

    @Test func connectAndAttach() async throws {
        try await wait(sec: 4)

        guard let engine = engineManager else { return }

        var fader: Fader? = try await Fader()

        try await engine.connectAndAttach(fader!.avAudioNode, to: engine.outputNode)

        fader = nil
        
        try await wait(sec: 4)
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
