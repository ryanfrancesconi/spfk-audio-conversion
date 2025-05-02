// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AudioToolbox

public struct AutomationTaper {
    public var taperUp: AUValue = 3
    public var taperDown: AUValue { 1 / taperUp }
    public var skew: AUValue = 0.333

    public init(taperUp: AUValue, skew: AUValue) {
        self.taperUp = taperUp
        self.skew = skew
    }
}

// MARK: - Presets

extension AutomationTaper {
    /// Straight line
    public static let linear = AutomationTaper(taperUp: 1, skew: 0)

    /// Half pipe
    public static let audio = AutomationTaper(taperUp: 3, skew: 1 / 3)

    /// Inverse of audio
    public static let reverseAudio = AutomationTaper(taperUp: 1 / 3, skew: 1 / 3)
}
