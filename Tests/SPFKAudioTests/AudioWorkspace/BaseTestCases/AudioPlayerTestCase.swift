// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import SPFKTime
import Testing

@testable import SPFKAudio

class AudioPlayerTestCase: AudioWorkspaceTestCase {
    var player: FilePlayer?

    override func setup() async throws {
        try await super.setup()

        let masterMixer = try #require(audioWorkspace.masterTrack?.mixer)

        let player = FilePlayer()
        self.player = player

        try await audioWorkspace.engineManager.connectAndAttach(
            player,
            to: masterMixer
        )
    }
}
