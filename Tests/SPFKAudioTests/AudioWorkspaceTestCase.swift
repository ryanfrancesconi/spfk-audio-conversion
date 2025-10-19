// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

public class AudioWorkspaceTestCase: BinTestCase {
    public let audioWorkspace = AudioWorkspace()

    var audioUnitChain: AudioUnitChain? { audioWorkspace.master?.audioUnitChain }

    public func setup() async throws {
        try await audioWorkspace.rebuild()

        try audioWorkspace.start()
    }
}

class AudioPlayerTestCase: AudioWorkspaceTestCase {
    var player: AudioFilePlayer?

    override public func setup() async throws {
        try await super.setup()
        
        let masterMixer = try #require(audioWorkspace.master?.mixer)

        let player = AudioFilePlayer()
        self.player = player
        try audioWorkspace.engineManager.connectAndAttach(player, to: masterMixer)
    }
}
