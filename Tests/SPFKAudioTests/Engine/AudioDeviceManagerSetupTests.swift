// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

@preconcurrency import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioDeviceManagerSetupTests: TestCaseModel, AudioDeviceManagerDelegate {
    let engine = AVAudioEngine()

    var audioEngineOutputNode: AVAudioOutputNode? {
        engine.outputNode
    }

    var audioEngineInputNode: AVAudioInputNode? {
        get async { engine.inputNode }
    }

    func audioDeviceManager(event: SPFKAudio.AudioDeviceManager.Event) async {
        Log.debug(event)
    }

    @Test func customSettings() async throws {
        let dm = AudioDeviceManager(delegate: self)

        let settings = AudioDeviceSettings(inputUID: "inputDeviceDisabledUID", outputUID: "BuiltInSpeakerDevice")

        try await dm.setup(settings: settings)

        let selectedOutputDevice = await dm.selectedOutputDevice
        let outputUID = await settings.outputUID

        #expect(selectedOutputDevice?.uid == outputUID)

        let defaultOutputDevice = await dm.hardware.defaultOutputDevice

        Log.debug("defaultOutputDevice", defaultOutputDevice)
    }
}
