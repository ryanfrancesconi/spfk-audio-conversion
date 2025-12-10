// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioDeviceManagerSetupTests: TestCaseModel {
    @Test func customSettings() async throws {
        let dm = AudioDeviceManager()

        let settings = AudioDeviceSettings(inputUID: "inputDeviceDisabledUID", outputUID: "com_uaudio_driver_UAD2AudioEngine:0")

        try await dm.setup(settings: settings)

        let selectedOutputDevice = await dm.selectedOutputDevice
        let outputUID = await settings.outputUID

        #expect(selectedOutputDevice?.uid == outputUID)

        let defaultOutputDevice = await dm.defaultOutputDevice
    }
}
