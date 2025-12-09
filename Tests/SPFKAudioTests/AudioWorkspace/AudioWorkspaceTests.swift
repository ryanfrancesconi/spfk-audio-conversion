// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioWorkspaceTests: AudioWorkspaceTestCase {
    var dm: AudioDeviceManager { audioWorkspace.deviceManager }
    var em: AudioEngineManager { audioWorkspace.engineManager }

    @Test func connectAndAttach() async throws {
        try await wait(sec: 4)

        try await setup()

        let master = try #require(audioWorkspace.masterTrack)

        var nodes: [AVAudioNode] = .init()

        for _ in 0 ..< 100 {
            nodes.append(AVAudioPlayerNode())
        }

        for node in nodes {
            try await audioWorkspace.connectAndAttach(node, to: master.mixer.mixerNode, format: nil)
        }

        #expect(master.mixer.mixerNode.inputs.count == 100)

        for input in master.mixer.mixerNode.inputs {
            try input.node?.detach()
        }

        try await tearDown()
        try await wait(sec: 5)
    }
}
