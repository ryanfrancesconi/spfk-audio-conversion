import Foundation

public enum WaveformDrawingResolution: CaseIterable {
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
}
