//  Copyright © 2020 Audio Design Desk. All rights reserved.

import AVFoundation

extension MixerWrapper: EngineNode {
    public var inputNode: AVAudioNode? { mixerNode }
    public var outputNode: AVAudioNode? { mixerNode }

    public func detach() {
        detachNodes()
    }
}

extension MixerWrapper: EngineNodeAU {
    public var avAudioNode: AVAudioNode { mixerNode }
}

/// Wrapper for Apple's Mixer Node. Mixes a variadic list of nodes.
public class MixerWrapper: Mixable {
    /// The internal mixer node
    public private(set) var mixerNode = AVAudioMixerNode()

    private var _volume: AUValue = 1.0
    /// Output Volume (Default 1)
    public var volume: AUValue {
        get { _volume }
        set {
            guard !isBypassed else { return }

            _volume = max(newValue, 0)
            mixerNode.outputVolume = _volume
        }
    }

    private var _pan: AUValue = 0

    /// Output Pan (Default 0 = center)
    public var pan: AUValue {
        get { _pan }

        set {
            guard !isBypassed else { return }

            _pan = newValue.clamped(to: -1 ... 1)
            mixerNode.pan = _pan
        }
    }

    /// Not really bypassed in this case, just unity volume and centered.
    /// Used for neutral rendering where this mixer is in line of the signal
    /// path.
    public var isBypassed: Bool = false {
        didSet {
            if isBypassed {
                mixerNode.outputVolume = 1
                mixerNode.pan = 0

            } else {
                mixerNode.pan = pan
                mixerNode.outputVolume = volume
            }
        }
    }

    public init() {
    }
}
