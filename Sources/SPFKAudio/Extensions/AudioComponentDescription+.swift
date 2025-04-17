import AudioToolbox
import SPFKUtils

public extension AudioComponentDescription {
    /// Wildcard definition for AudioComponentCount lookup for any
    /// audio component
    static var wildcard: AudioComponentDescription {
        AudioComponentDescription(
            componentType: 0,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    // due to lack of Equatable
    func matches(_ other: AudioComponentDescription) -> Bool {
        componentType == other.componentType &&
            componentSubType == other.componentSubType &&
            componentManufacturer == other.componentManufacturer
    }

    var supportsIO: Bool {
        isEffect || isFormatConverter
    }

    var isEffect: Bool {
        componentType == kAudioUnitType_Effect ||
            componentType == kAudioUnitType_MusicEffect
    }

    var isFormatConverter: Bool {
        componentType == kAudioUnitType_FormatConverter
    }

    var isMusicDevice: Bool {
        componentType == kAudioUnitType_MusicDevice
    }

    var isGenerator: Bool {
        componentType == kAudioUnitType_Generator
    }

    var validationCommand: String {
        "auval -v \(componentType.fourCharCodeToString() ?? "") " +
            "\(componentSubType.fourCharCodeToString() ?? "") " +
            "\(componentManufacturer.fourCharCodeToString() ?? "")"
    }
}
