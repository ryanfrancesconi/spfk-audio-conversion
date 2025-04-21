// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

// Edited to just misc necessary items

import AudioToolbox

@inline(__always)
internal func AudioUnitGetParameter(_ unit: AudioUnit, param: AudioUnitParameterID) -> AUValue {
    var val: AudioUnitParameterValue = 0
    AudioUnitGetParameter(unit, param, kAudioUnitScope_Global, 0, &val)
    return val
}

@inline(__always)
internal func AudioUnitSetParameter(_ unit: AudioUnit, param: AudioUnitParameterID, to value: AUValue) {
    AudioUnitSetParameter(unit, param, kAudioUnitScope_Global, 0, AudioUnitParameterValue(value), 0)
}

public extension AUParameterTree {
    static func createParameter(identifier: String,
                                name: String,
                                address: AUParameterAddress,
                                range: ClosedRange<AUValue>,
                                unit: AudioUnitParameterUnit,
                                flags: AudioUnitParameterOptions) -> AUParameter {
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

/// Helper function to convert codes for Audio Units
/// - parameter string: Four character string to convert
public func fourCC(_ string: String) -> UInt32 {
    let utf8 = string.utf8

    precondition(utf8.count == 4, "Must be a 4 character string")

    var out: UInt32 = 0

    for char in utf8 {
        out <<= 8
        out |= UInt32(char)
    }
    return out
}

extension AudioUnitParameterOptions {
    /// Default options
    public static let `default`: AudioUnitParameterOptions = [
        .flag_IsReadable,
        .flag_IsWritable,
        .flag_CanRamp,
    ]
}
