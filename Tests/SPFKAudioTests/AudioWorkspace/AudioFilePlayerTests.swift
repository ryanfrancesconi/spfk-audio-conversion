// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime))
final class AudioFilePlayerTests: AudioPlayerTestCase {
    @Test func testEdit() async throws {
        try await setup()

        let player = try #require(player)
        
        player.volume = 1
        try player.load(url: BundleResources.shared.tabla_wav)
        try player.schedule(from: 1, to: 2)

        #expect(player.editRange == 1 ... 2)

        try player.play()
        #expect(player.isPlaying)

        try await wait(sec: 1)
        
        player.stop()
        #expect(!player.isPlaying)

       try audioWorkspace.stop()
    }
}
