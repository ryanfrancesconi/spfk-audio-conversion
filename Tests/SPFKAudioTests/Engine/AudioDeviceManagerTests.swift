// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing
import SimplyCoreAudio

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioDeviceManagerTests: TestCaseModel {
    var dm: AudioDeviceManager = .init()

    @Test func changeSampleRate() async throws {
        let inputDevice = try #require(dm.selectedInputDevice)
        let outputDevice = try #require(dm.selectedOutputDevice)

        try await testSampleRates(for: inputDevice)
        try await testSampleRates(for: outputDevice)
    }

    func testSampleRates(for device: AudioDevice) async throws {
        let supportedSampleRates = dm.supportedSampleRates(for: device)

        Log.debug(device.name, supportedSampleRates)

        let sampleRate = try #require(device.nominalSampleRate)

        #expect(throws: Error.self) {
            try dm.setSampleRate(device: device, to: 8000)
        }

        for rate in supportedSampleRates {
            try dm.setSampleRate(device: device, to: rate)

            try await wait(sec: 1)

            #expect(device.nominalSampleRate == rate)
        }

        try dm.setSampleRate(device: device, to: sampleRate)

        try await wait(sec: 1)

        // will be ignored
        try dm.setSampleRate(device: device, to: sampleRate)
    }
}
