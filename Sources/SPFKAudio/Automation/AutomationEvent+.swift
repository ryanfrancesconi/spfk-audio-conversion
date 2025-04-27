import Foundation
import SPFKAudioC

extension AutomationEvent: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startTime == rhs.startTime &&
            lhs.rampDuration == rhs.rampDuration &&
            lhs.startTime == rhs.startTime
    }
}
