import Foundation

public enum WaveformDrawingResolution: CaseIterable, Equatable, Codable {
    case low
    case medium
    case high
    case veryHigh
    case lossless

    /// The amount of samples to buffer for a maximumMagnitude of for each point
    public var samplesPerPoint: Int {
        switch self {
        case .low:
            128
        case .medium:
            64
        case .high:
            32
        case .veryHigh:
            16
        case .lossless:
            1
        }
    }

    /// Chooses a suggested value based on an audio file's duration
    /// - Parameter duration: the audio duration
    public init(duration: TimeInterval) {
        let duration = max(0, duration)

        switch duration {
        case 0 ..< 2:
            self = .lossless

        case 2 ..< 10:
            self = .veryHigh

        case 10 ..< 20:
            self = .high

        case 20...:
            self = .medium

        default:
            self = .medium
        }
    }

    /// Returns an exact match or averages into a range to one of the preset values
    public init(samplesPerPoint: Int) {
        let samplesPerPoint = max(1, samplesPerPoint)

        for item in Self.allCases where item.samplesPerPoint == samplesPerPoint {
            self = item
            return
        }

        let low = Self.low.samplesPerPoint
        let medium = Self.medium.samplesPerPoint
        let high = Self.high.samplesPerPoint
        let veryHigh = Self.veryHigh.samplesPerPoint

        switch samplesPerPoint {
        case low ..< medium:
            self = .low

        case medium ..< high:
            self = .medium

        case high ..< veryHigh:
            self = .high

        case veryHigh...:
            self = .veryHigh

        default:
            self = .medium
        }
    }
}
