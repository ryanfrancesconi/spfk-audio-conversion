import Foundation

public enum WaveformDrawingResolution: CaseIterable {
    case low
    case medium
    case high
    case veryHigh

    /// The amount of samples to take maximumMagnitude of for each point
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
        }
    }
}
