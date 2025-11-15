// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SimplyCoreAudio
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioWorkspaceTests: AudioWorkspaceTestCase {
    var dm: AudioDeviceManager { audioWorkspace.deviceManager }
    var em: AudioEngineManager { audioWorkspace.engineManager }

    @Test func checkNotifications() async throws {
        try await setup()

        guard let device = dm.selectedOutputDevice else { return }

        guard let supportedSampleRates = device.nominalSampleRates else {
            throw NSError(description: "failed to get sample rates from \(device.name)")
        }
        
        let currentSampleRate = try #require(dm.selectedOutputDevice?.nominalSampleRate)
        
        let nextRate = try #require(
            supportedSampleRates.first { rate in
                rate != currentSampleRate
            }
        )

        try dm.setOutputSampleRate(to: nextRate)

        try await wait(sec: 2)

        try dm.setOutputSampleRate(to: currentSampleRate)
    }
}
