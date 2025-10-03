// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AudioToolbox

/// Base protocol for any type supported by @Parameter
public protocol NodeParameterType {
    /// Get the float value
    func toAUValue() -> AUValue
    /// Initialize with a floating point number
    /// - Parameter value: initial value
    init(_ value: AUValue)
}

extension Bool: NodeParameterType {
    /// Convert a Boolean to a floating point number
    /// - Returns: An AUValue
    public func toAUValue() -> AUValue {
        self ? 1.0 : 0.0
    }

    /// Initialize with a value
    /// - Parameter value: Initial value
    public init(_ value: AUValue) {
        self = value > 0.5
    }
}

extension AUValue: NodeParameterType {
    /// Convert to AUValue
    /// - Returns: Value of type AUValue
    public func toAUValue() -> AUValue {
        self
    }
}
