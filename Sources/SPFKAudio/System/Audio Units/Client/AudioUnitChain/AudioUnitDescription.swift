import AEXML
import AppKit
import AudioToolbox
import AVFoundation
import SPFKUtils

/// A wrapper for the `AVAudioUnit` to allow an independent bypass property
/// which doesn't rely on the `AUAudioUnit` one
public class AudioUnitDescription: Equatable {
    public static func == (lhs: AudioUnitDescription, rhs: AudioUnitDescription) -> Bool {
        lhs.avAudioUnit == rhs.avAudioUnit
    }

    public private(set) var name: String?

    public var audioComponentDescription: AudioComponentDescription {
        avAudioUnit.audioComponentDescription
    }

    private var _isBypassed = false

    /// Keep a bypassed flag separate from the audio units as they can be unreliable
    /// Test that, if it's true keep this class otherwise, make the array just [AVAudioUnit]
    public var isBypassed: Bool {
        get { _isBypassed }
        set {
            _isBypassed = newValue
            // the audio unit may or may not agree to this
            avAudioUnit.auAudioUnit.shouldBypassEffect = newValue
        }
    }

    public var fullStatePlist: AEXMLElement? {
        AudioUnitState.fullStateDocument(for: avAudioUnit)?.root
    }

    public private(set) var avAudioUnit: AVAudioUnit

    public init(avAudioUnit: AVAudioUnit) {
        self.avAudioUnit = avAudioUnit
        name = avAudioUnit.auAudioUnit.audioUnitName
    }

    public func dispose() {
        avAudioUnit.auAudioUnit.musicalContextBlock = nil
        avAudioUnit.auAudioUnit.transportStateBlock = nil
        avAudioUnit.detach()
    }

    deinit {
        Log.debug("* { AudioUnitDescription \(name ?? "?") }")
    }
}
