// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioDeviceManagerTests: TestCaseModel {
    let dm: AudioDeviceManager

    init() async {
        dm = AudioDeviceManager()
        do {
            try await dm.setup()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    @Test func printDescription() async throws {
        try await Log.debug(dm.detailedDescription())
    }

    @Test(arguments: [Scope.output])
    func deviceSampleRates(scope: Scope) async throws {
        let devices = scope == .output ?
            try await dm.hardware.outputDevices() :
            try await dm.hardware.inputDevices()

        for device in devices {
            try await testSampleRates(for: device, scope: scope)
        }
    }

    func testSampleRates(for device: AudioDevice, scope: Scope) async throws {
        guard let nominalSampleRates = device.getNominalSampleRates(scope: scope) else {
            throw NSError(description: "failed to get sample rates from \(device.name)")
        }

        Log.debug("nominalSampleRates", device.name, scope, nominalSampleRates)

        let currentRate = try #require(device.nominalSampleRate)

        guard nominalSampleRates.count > 1 else {
            return // ignore devices that only have 1 sample rates
        }

        await #expect(throws: Error.self) {
            try await dm.setSampleRate(device: device, to: 1024)
        }

        for rate in nominalSampleRates {
            do {
                try await dm.setSampleRate(device: device, to: rate)

            } catch {
                Issue.record(error)
            }
        }

        do {
            try await dm.setSampleRate(device: device, to: currentRate) // put it back
        } catch {
            Issue.record(error)
        }
    }

    @Test func setSampleRateOfSelectedOutputDevice() async throws {
        guard let device = await dm.selectedOutputDevice else { return }

        guard let supportedSampleRates = device.nominalSampleRates else {
            throw NSError(description: "failed to get sample rates from \(device.name)")
        }

        let currentSampleRate = try await #require(dm.selectedOutputDevice?.nominalSampleRate)

        let nextRate = try #require(
            supportedSampleRates.first { rate in
                rate != currentSampleRate
            }
        )

        try await dm.setOutputSampleRate(to: nextRate)
        #expect(device.nominalSampleRate == nextRate)

        try await dm.setOutputSampleRate(to: currentSampleRate)
        #expect(device.nominalSampleRate == currentSampleRate)
    }
}

extension AudioDeviceManagerTests {
    @Test(arguments: [Scope.output])
    func preferredChannelsForStereoAllDevices(scope: Scope) async throws {
        let devices = try await dm.hardware.allDevices()

        for device in devices {
            let preferredChannels = device.preferredChannelsForStereo(scope: scope)

            Log.debug(device.name, preferredChannels)
        }
    }
}
