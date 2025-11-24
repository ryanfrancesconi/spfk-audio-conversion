import AVFoundation
import SPFKBase

extension AudioTrack: EngineNode {
    public var inputNode: AVAudioNode? { mixer.avAudioNode }
    public var outputNode: AVAudioNode? { fader.avAudioNode }
}

public class AudioTrack {
    /// input
    public let mixer: MixerWrapper

    /// output
    public let fader: Fader

    /// effects
    public let audioUnitChain: AudioUnitChain

    public weak var delegate: AudioTrackDelegate?

    public init(delegate: AudioTrackDelegate? = nil) async throws {
        self.delegate = delegate

        mixer = MixerWrapper()
        fader = try await Fader()
        audioUnitChain = AudioUnitChain()
        audioUnitChain.delegate = self

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
        self.delegate?.availableAudioUnitComponents
    }
}

public protocol AudioTrackDelegate: AnyObject, AudioEngineConnection, AudioUnitAvailability {}
