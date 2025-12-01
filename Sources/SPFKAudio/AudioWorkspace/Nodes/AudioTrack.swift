// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public final class AudioTrack: @unchecked Sendable {
    /// input
    public let mixer: MixerWrapper

    /// output
    public let fader: Fader

    /// effects
    public private(set) lazy var audioUnitChain: AudioUnitChain = .init(delegate: self)

    public let delegate: AudioTrackDelegate?

    public init(delegate: AudioTrackDelegate?) async throws {
        self.delegate = delegate

        mixer = MixerWrapper()
        fader = try await Fader()

        try await audioUnitChain.updateIO(input: mixer.avAudioNode, output: fader.avAudioNode)
    }

    deinit {
        Log.debug("* { \(self) }")
    }
}

extension AudioTrack: AudioUnitChainDelegate {
    public func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) async throws {
        try await delegate?.connectAndAttach(node1, to: node2, format: format)
    }

    public func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChain.Event) {
        Log.debug(event)
    }

    public var availableAudioUnitComponents: [AVAudioUnitComponent]? {
        delegate?.availableAudioUnitComponents
    }
}

extension AudioTrack: EngineNode {
    public var inputNode: AVAudioNode? { mixer.avAudioNode }
    public var outputNode: AVAudioNode? { fader.avAudioNode }
}

public protocol AudioTrackDelegate: AnyObject, AudioEngineConnection, AudioUnitAvailability {}
