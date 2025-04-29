import Foundation
import SPFKAudioC

// MARK: These are extending the C struct in ParameterAutomation.h

extension AutomationEvent: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startTime == rhs.startTime &&
            lhs.rampDuration == rhs.rampDuration &&
            lhs.targetValue == rhs.targetValue
    }
}

extension ParameterAutomationPoint: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startTime == rhs.startTime &&
            lhs.rampDuration == rhs.rampDuration &&
            lhs.targetValue == rhs.targetValue &&
            lhs.rampTaper == rhs.rampTaper &&
            lhs.rampSkew == rhs.rampSkew
    }

    /// Initialize with value, time, and duration
    /// - Parameters:
    ///   - targetValue: Target value
    ///   - startTime: Start time
    ///   - rampDuration: Ramp duration
    public init(targetValue: AUValue, startTime: Float, rampDuration: Float) {
        self.init(targetValue: targetValue,
                  startTime: startTime,
                  rampDuration: rampDuration,
                  rampTaper: 1,
                  rampSkew: 0)
    }

    /// Check for linearity
    /// - Returns: True if linear
    public func isLinear() -> Bool {
        rampTaper == 1.0 && rampSkew == 0.0
    }
}
