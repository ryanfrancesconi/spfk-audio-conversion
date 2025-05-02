// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime))
final class AudioUnitChainTests: AudioEngineTestCase {
    @Test func testInsert() async throws {
        try await setup()

        try await audioUnitChain.insertAudioUnit(componentDescription: auDelayDesc, at: 0)
        try await audioUnitChain.insertAudioUnit(componentDescription: auMatrixReverb, at: 1)
        try await audioUnitChain.connect()

        await #expect(audioUnitChain.data.unbypassedEffects.count == 2)

        player.volume = 0.1
        try player.load(url: BundleResources.shared.tabla_wav)
        try player.schedule()
        try player.play()

        try await wait(sec: 1)
        player.stop()
        try await wait(sec: 2)

        _engineManager.stopEngine()
    }

    @Test func testInsertOutOfBounds() async throws {
        try await setup()

        await #expect(throws: (any Error).self) {
            try await self.audioUnitChain.insertAudioUnit(componentDescription: self.auDelayDesc, at: self.audioUnitChain.insertCount + 1)
        }
    }
}
