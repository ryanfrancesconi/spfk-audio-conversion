// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.realtime))
final class AudioUnitChainTests: AudioPlayerTestCase, @unchecked Sendable {
    @Test func findEffects() async throws {
        let components = [
            AVAudioUnitComponent.component(matching: auDelayDesc),
            AVAudioUnitComponent.component(matching: auMatrixReverbDesc),
        ].compactMap { $0 }

        #expect(components.count == 2)
    }

    @Test func insert() async throws {
        try await setup()

        let audioUnitChain = try #require(audioUnitChain)
        let player = try #require(player)

        try await audioUnitChain.insertAudioUnit(componentDescription: auDelayDesc, at: 0)
        try await audioUnitChain.insertAudioUnit(componentDescription: auMatrixReverbDesc, at: 1)
        try await audioUnitChain.connect()

        await #expect(audioUnitChain.data.unbypassedEffects.count == 2)

        player.volume = 1
        try player.load(url: TestBundleResources.shared.tabla_wav)
        try player.schedule()
        try player.play()

        try await wait(sec: 1)
        player.stop()
        try await wait(sec: 2)

        try audioWorkspace.stop()
    }

    @Test func insertOutOfBounds() async throws {
        try await setup()
        let audioUnitChain = try #require(audioUnitChain)

        await #expect(throws: (any Error).self) {
            try await audioUnitChain.insertAudioUnit(
                componentDescription: self.auDelayDesc, at: audioUnitChain.insertCount + 1)
        }
    }
}
