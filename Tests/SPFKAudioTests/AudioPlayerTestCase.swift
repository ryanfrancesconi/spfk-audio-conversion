// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

class AudioPlayerTestCase: BinTestCase {
    var audioWorkspace = AudioWorkspace()

    var player: AudioFilePlayer?
    var audioUnitChain: AudioUnitChain? { audioWorkspace.masterAudioUnitChain }

    func setup() async throws {
        try await audioWorkspace.rebuild()

        let masterMixer = try #require(audioWorkspace.masterMixer)

        let player = AudioFilePlayer()
        self.player = player
        try audioWorkspace.engineManager.connectAndAttach(player, to: masterMixer)

        try audioWorkspace.start()
    }
}
