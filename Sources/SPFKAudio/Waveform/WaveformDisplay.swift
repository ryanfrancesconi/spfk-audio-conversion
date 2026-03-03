import Foundation

public enum WaveformDisplay: Sendable, Codable {
    /// Flips the negative parts of the waveform to become positive, making the whole signal positive.
    case rectifiedFull

    /// Keeps only the positive (or negative) part of the waveform and discards the other half, creating gaps.
    case rectifiedHalf

    /// Shows the whole signal's energy, positive and negative
    case full

    public var minimum: Float {
        self == .full ? -1 : 0
    }

    public var maximum: Float { 1 }
}

public enum WaveformQuality: CGFloat, CaseIterable, Sendable, Codable {
    case minimum = 1
    case low = 2
    case medium = 5
    case high = 8
    case maximum = 10

    public var label: String {
        switch self {
        case .minimum:
            "Minimum"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .maximum:
            "Maximum"
        }
    }
}
