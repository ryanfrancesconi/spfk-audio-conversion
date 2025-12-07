// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import SPFKAudioC
import SPFKBase

// swiftformat:disable consecutiveSpaces

/// Extends the `FaderParameter` enum defined in `SPFKAudioC`
extension FaderParameter {
    /// Gain can be any non-negative number -- however 0 - 4 is
    /// a practical range: 0 ... +12dB
    public static let defaultGainRange: ClosedRange<AUValue> = 0 ... 4
    
    var parameterAddress: AUParameterAddress { rawValue }

    var identifier: String {
        switch self {
        case .leftGain:     "leftGain"
        case .rightGain:    "rightGain"
        case .flipStereo:   "flipStereo"
        case .mixToMono:    "mixToMono"
        @unknown default:   ""
        }
    }

    var addressName: String {
        switch self {
        case .leftGain:     "FaderParameterLeftGain"
        case .rightGain:    "FaderParameterRightGain"
        case .flipStereo:   "FaderParameterFlipStereo"
        case .mixToMono:    "FaderParameterMixToMono"
        @unknown default:   ""
        }
    }

    var name: String {
        switch self {
        case .leftGain:     "Left Gain"
        case .rightGain:    "Right Gain"
        case .flipStereo:   "Flip Stereo"
        case .mixToMono:    "Mix To Mono"
        @unknown default:   ""
        }
    }

    var range: ClosedRange<AUValue> {
        switch self {
        case .leftGain,
             .rightGain:    Self.defaultGainRange
        case .flipStereo,
             .mixToMono:    AUValue.unitIntervalRange
        @unknown default:   AUValue.unitIntervalRange
        }
    }

    var unit: AudioUnitParameterUnit {
        switch self {
        case .leftGain,
             .rightGain:    .linearGain
        case .flipStereo,
             .mixToMono:    .boolean

        @unknown default:   .linearGain
        }
    }

    var defaultValue: AUValue {
        switch self {
        case .leftGain,
             .rightGain:    1
        case .flipStereo,
             .mixToMono:    0
        @unknown default:   0
        }
    }

    var parameterDef: NodeParameterDef {
        NodeParameterDef(
            identifier: identifier,
            name: name,
            address: getParameterAddressDSP(addressName),
            defaultValue: defaultValue,
            range: range,
            unit: .boolean
        )
    }
}

// swiftformat:enable consecutiveSpaces
