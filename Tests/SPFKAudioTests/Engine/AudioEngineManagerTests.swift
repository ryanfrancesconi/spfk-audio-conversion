// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKAudio
import SPFKTesting
import SPFKBase
import Testing

@Suite(.serialized, .tags(.engine))
final class AudioEngineManagerTests {
    @Test func state() async throws {
        let engineManager = AudioEngineManager()
        engineManager.delegate = self

        try engineManager.startEngine()
        #expect(engineManager.engineIsRunning)

        Log.debug(engineManager.debugDescription)

        await engineManager.rebuildEngine()
        #expect(!engineManager.engineIsRunning)

        try engineManager.startEngine()
        #expect(engineManager.engineIsRunning)

        engineManager.stopEngine()
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
