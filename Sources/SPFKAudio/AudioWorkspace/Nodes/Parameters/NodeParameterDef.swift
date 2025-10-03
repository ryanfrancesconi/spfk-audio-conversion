// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import SPFKUtils

/// Definition or specification of a node parameter
public struct NodeParameterDef {
    public var identifier: String
    public var name: String
    public var address: AUParameterAddress
    public var defaultValue: AUValue = 0.0
    public var range: ClosedRange<AUValue>
    public var unit: AudioUnitParameterUnit
    public var flags: AudioUnitParameterOptions

    /// Initialize node parameter definition with all data
    public init(
        identifier: String,
        name: String,
        address: AUParameterAddress,
        defaultValue: AUValue,
        range: ClosedRange<AUValue>,
        unit: AudioUnitParameterUnit,
        flags: AudioUnitParameterOptions = .default
    ) {
        self.identifier = identifier
        self.name = name
        self.address = address
        self.defaultValue = defaultValue
        self.range = range
        self.unit = unit
        self.flags = flags
    }
}
