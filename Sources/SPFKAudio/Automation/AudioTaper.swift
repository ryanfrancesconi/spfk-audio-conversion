// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AudioToolbox

public struct AudioTaper {
    public var value: AUValue = 3
    public var inverseValue: AUValue { 1 / value }
    public var skew: AUValue = 0.333

    public init(value: AUValue, skew: AUValue) {
        self.value = value
        self.skew = skew
    }
}

// MARK: - Presets

extension AudioTaper {
    /// Half pipe
    public static let `default` = AudioTaper(value: 3, skew: 1 / 3)

    /// Straight line
    public static let linear = AudioTaper(value: 1, skew: 0)

    /// Inverse of .audio
    public static let reverseAudio = AudioTaper(value: 1 / 3, skew: 1 / 3)
}
