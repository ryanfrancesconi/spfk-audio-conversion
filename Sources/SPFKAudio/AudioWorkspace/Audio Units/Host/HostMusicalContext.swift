import Foundation

public struct HostMusicalContext: Sendable {
    public var currentTempo: Double = 120
    public var timeSignatureNumerator: Double = 4
    public var timeSignatureDenominator: Int = 4

    /// the fractional bar number * timeSignatureNumerator
    public var currentBeatPosition: Double = 0

    public var currentMeasureDownbeatPosition: Double = 0
    public var sampleOffsetToNextBeat: Int = 0
}
