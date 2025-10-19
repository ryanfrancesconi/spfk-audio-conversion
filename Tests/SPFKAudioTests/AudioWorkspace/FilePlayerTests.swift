// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime))
final class FilePlayerTests: AudioPlayerTestCase {
    @Test func edit() async throws {
        try await setup()
        let player = try #require(player)
        try player.load(url: BundleResources.shared.tabla_wav)

        let duration = try #require(player.duration)
        #expect(duration == 4.39375)

        try player.schedule()
        #expect(player.playbackRange == 0 ... duration)
        #expect(player.editedDuration == duration)

        try player.schedule(from: 0, to: duration)
        #expect(player.playbackRange == 0 ... duration)

        try player.schedule(from: 0)
        #expect(player.playbackRange == 0 ... duration)

        try player.schedule(from: duration - 1)
        #expect(player.playbackRange == duration - 1 ... duration)
        #expect(player.editedDuration == 1)

        try player.schedule(to: 3)
        #expect(player.playbackRange == 0 ... 3)
        #expect(player.editedDuration == 3)

        try player.schedule(from: 1, to: 3)
        #expect(player.playbackRange == 1 ... 3)
        #expect(player.editedDuration == 2)

        #expect(throws: (any Error).self) {
            try player.schedule(from: 4, to: 3)
        }

        try player.schedule(from: 0, to: duration + 1)
        #expect(player.playbackRange == 0 ... duration)

        try player.schedule(from: -1, to: duration)
        #expect(player.playbackRange == 0 ... duration)

        try audioWorkspace.stop()
    }

    @Test func play() async throws {
        try await setup()

        let player = try #require(player)
        player.volume = 0.5

        try player.load(url: BundleResources.shared.tabla_wav)
        try player.schedule(from: 1, to: 3)
        try player.play()

        #expect(player.isPlaying)

        // just for rough example of internal player time
        let timeTask = Task {
            while player.isPlaying {
                do {
                    try Task.checkCancellation()

                    Log.debug(player.currentFrame, player.currentTime)

                    try await Task.sleep(seconds: 0.1)

                } catch {
                    Log.error(error)
                    break
                }
            }
        }

        try await wait(sec: 2)

        timeTask.cancel()

        player.stop()
        #expect(!player.isPlaying)

        try audioWorkspace.stop()
    }
}
