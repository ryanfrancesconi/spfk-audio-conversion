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

    @Test func changeSampleRate() async throws {
        for device in await dm.allDevices {
            try await testSampleRates(for: device)
        }
    }

    func testSampleRates(for device: AudioDevice) async throws {
        guard let supportedSampleRates = device.nominalSampleRates else {
            throw NSError(description: "failed to get sample rates from \(device.name)")
        }

        Log.debug(device.name, supportedSampleRates)

        let sampleRate = try #require(device.nominalSampleRate)

        await #expect(throws: Error.self) {
            try await dm.setSampleRate(device: device, to: 8000)
        }

        for rate in supportedSampleRates {
            try await dm.setSampleRate(device: device, to: rate)

            #expect(device.nominalSampleRate == rate, "\(device.name)")
        }

        try await dm.setSampleRate(device: device, to: sampleRate)

        try await wait(sec: 1)

        // will be ignored
        try await dm.setSampleRate(device: device, to: sampleRate)
    }
}
