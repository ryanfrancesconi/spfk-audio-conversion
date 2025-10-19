// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime))
final class AudioFilePlayerTests: AudioPlayerTestCase {
    @Test func edit() async throws {
        try await setup()

        let player = try #require(player)

        player.volume = 1
        try player.load(url: BundleResources.shared.tabla_wav)

        let hostTime = mach_absolute_time()
        try player.schedule(from: 1, to: 3, when: 0, hostTime: hostTime)

        #expect(player.editRange == 1 ... 3)

        try player.play()
        #expect(player.isPlaying)

        let timeTask = Task {
            while player.isPlaying {
                do {
                    try Task.checkCancellation()

                    Log.debug(player.currentFrame, player.currentTime)

                    try await Task.sleep(seconds: 0.1)

                } catch {
                    break
                }
            }
        }

        try await wait(sec: 2)

        // #expect(player.currentTime == 1)

        timeTask.cancel()

        player.stop()
        #expect(!player.isPlaying)

        try player.detachNodes()

        try audioWorkspace.stop()
    }
}
