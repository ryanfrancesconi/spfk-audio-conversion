// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import SPFKTime
import Testing

@testable import SPFKAudio

class TransportPlayerTestCase: AudioWorkspaceTestCase, @unchecked Sendable {
    var player: TransportPlayer?

    override func setup() async throws {
        try await super.setup()

        let masterMixer = try #require(audioWorkspace.masterTrack?.mixer)

        let player = try await TransportPlayer(delegate: self)
        self.player = player

        try await audioWorkspace.engineManager.connectAndAttach(
            player,
            to: masterMixer
        )
    }
}

extension TransportPlayerTestCase: TransportPlayerDelegate {
    func transportPlayer(amplitudeEvent event: [Float]) {}

    func transportPlayer(shouldRestartAtTime time: TimeInterval) {
        try? player?.play(time: time)
    }

    func transportPlayer(timerEvent event: TransportTimerEvent) {
        //        Log.debug(event)
    }

    func connectAndAttach(
        _ node1: AVAudioNode,
        to node2: AVAudioNode,
        format: AVAudioFormat?
    ) async throws {
        try await audioWorkspace.connectAndAttach(
            node1,
            to: node2,
            format: format
        )
    }
}
