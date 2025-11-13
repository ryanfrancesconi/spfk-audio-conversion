// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKTime
import SPFKUtils
import Testing

public class AudioWorkspaceTestCase: BinTestCase {
    public let audioWorkspace = AudioWorkspace()

    var audioUnitChain: AudioUnitChain? { audioWorkspace.master?.audioUnitChain }

    public func setup() async throws {
        try await audioWorkspace.rebuild()
        try audioWorkspace.start()
    }

    deinit {
        do {
            try audioWorkspace.stop()
        } catch {
            Log.error(error)
        }
    }
}

class AudioPlayerTestCase: AudioWorkspaceTestCase {
    var player: FilePlayer?

    override public func setup() async throws {
        try await super.setup()

        let masterMixer = try #require(audioWorkspace.master?.mixer)

        let player = FilePlayer()
        self.player = player

        try audioWorkspace.engineManager.connectAndAttach(player, to: masterMixer)
    }
}

class TransportPlayerTestCase: AudioWorkspaceTestCase {
    var player: TransportPlayer?

    override public func setup() async throws {
        try await super.setup()

        let masterMixer = try #require(audioWorkspace.master?.mixer)

        let player = try TransportPlayer(delegate: self)
        self.player = player

        try audioWorkspace.engineManager.connectAndAttach(player, to: masterMixer)
    }
}

extension TransportPlayerTestCase: TransportPlayerDelegate {
    func transportPlayer(amplitudeEvent event: [Float]) {
    }

    func transportPlayer(shouldRestartAtTime time: TimeInterval) {
        try? player?.play(time: time)
    }

    func transportPlayer(timerEvent event: TransportTimerEvent) {
        // Log.debug(event)
    }

    func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) throws {
        try audioWorkspace.connectAndAttach(node1, to: node2, format: format)
    }
}
