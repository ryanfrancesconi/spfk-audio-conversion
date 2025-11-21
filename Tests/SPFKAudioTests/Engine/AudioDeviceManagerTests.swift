// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKAudioHardware
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioDeviceManagerTests: TestCaseModel {
    let dm: AudioDeviceManager

    public init() async {
        dm = AudioDeviceManager()
        await dm.setup()
    }

    @Test func printDescription() async throws {
        Log.debug(await dm.detailedDescription)
    }

    @Test(arguments: [Scope.output, Scope.input])
    func deviceSampleRates(scope: Scope) async throws {
        let devices = await dm.allDevices.isOnly(scope: scope)

        for device in devices {
            #expect(await testSampleRates(for: device, scope: scope), "\(device.name) failed")
        }
    }

    func testSampleRates(for device: AudioDevice, scope: Scope) async -> Bool {
        do {
            guard let nominalSampleRates = device.getNominalSampleRates(scope: scope) else {
                throw NSError(description: "failed to get sample rates from \(device.name)")
            }

            Log.debug("nominalSampleRates", device.name, scope, nominalSampleRates)

            let currentRate = try #require(device.nominalSampleRate)

            guard nominalSampleRates.count > 1 else {
                return true // ignore devices that only have 1 sample rates
            }

            await #expect(throws: Error.self) {
                try await dm.setSampleRate(device: device, to: 1024)
            }

            for rate in nominalSampleRates {
                try await dm.setSampleRate(device: device, to: rate)

                guard device.nominalSampleRate == rate else {
                    throw NSError(description: "\(device.name) failed to set to \(rate)")
                }
            }

            try await dm.setSampleRate(device: device, to: currentRate) // put it back

            return true

        } catch {
            Log.error(error)
            return false
        }
    }
}
