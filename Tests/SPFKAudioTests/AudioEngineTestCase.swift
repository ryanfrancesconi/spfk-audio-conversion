// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

class AudioEngineTestCase: BinTestCase {
    let auDelayDesc = AudioComponentDescription(
        componentType: 1635083896,
        componentSubType: 1684368505,
        componentManufacturer: 1634758764,
        componentFlags: 2,
        componentFlagsMask: 0
    )

    let auMatrixReverb = AudioComponentDescription(
        componentType: 1635083896,
        componentSubType: 1836213622,
        componentManufacturer: 1634758764,
        componentFlags: 2,
        componentFlagsMask: 0
    )

    var _engineManager: AudioEngineManager = .init()
    var audioUnitChain: AudioUnitChain = .init()

    let player = AudioFilePlayer()
    let mixer = MixerWrapper()

    func setup() async throws {
        try _engineManager.setEngineOutput(to: mixer.mixerNode)
        try _engineManager.startEngine()
        audioUnitChain.delegate = self
        try await audioUnitChain.updateIO(input: player.playerNode, output: mixer.mixerNode)
    }
}

extension AudioEngineTestCase: AudioUnitChainDelegate {
    func audioUnitChain(_ audioUnitChain: SPFKAudio.AudioUnitChain, event: SPFKAudio.AudioUnitChain.Event) {
        Log.debug(event)
    }

    var engineManager: (any SPFKAudio.AudioEngineManagerModel)? {
        _engineManager
    }

    var availableAudioUnitComponents: [AVAudioUnitComponent]? {
        [
            AVAudioUnitComponent.component(matching: auDelayDesc),
            AVAudioUnitComponent.component(matching: auMatrixReverb),
        ].compactMap { $0 }
    }
}
