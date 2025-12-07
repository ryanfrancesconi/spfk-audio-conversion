// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AudioToolbox

@inline(__always)
func AudioUnitGetParameter(_ unit: AudioUnit, param: AudioUnitParameterID) -> AUValue {
    var val: AudioUnitParameterValue = 0
    AudioUnitGetParameter(unit, param, kAudioUnitScope_Global, 0, &val)
    return val
}

@inline(__always)
func AudioUnitSetParameter(_ unit: AudioUnit, param: AudioUnitParameterID, to value: AUValue) {
    AudioUnitSetParameter(unit, param, kAudioUnitScope_Global, 0, AudioUnitParameterValue(value), 0)
}

extension AUParameterTree {
    public static func createParameter(
        identifier: String,
        name: String,
        address: AUParameterAddress,
        range: ClosedRange<AUValue>,
        unit: AudioUnitParameterUnit,
        flags: AudioUnitParameterOptions
    ) -> AUParameter {
        AUParameterTree.createParameter(
            withIdentifier: identifier,
            name: name,
            address: address,
            min: range.lowerBound,
            max: range.upperBound,
            unit: unit,
            unitName: nil,
            flags: flags,
            valueStrings: nil,
            dependentParameters: nil
        )
    }
}

extension AUParameterTree {
    /// Look up paramters by key
    public subscript(key: String) -> AUParameter? {
        value(forKey: key) as? AUParameter
    }
}

extension AudioUnitParameterOptions {
    /// Default options
    public static let `default`: AudioUnitParameterOptions = [
        .flag_IsReadable,
        .flag_IsWritable,
        .flag_CanRamp,
    ]
}
