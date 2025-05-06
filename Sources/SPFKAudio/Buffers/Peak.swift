import AVFoundation
import Foundation
import SPFKUtils

public struct Peak: Equatable {
    internal static let min: Float = -10000.0

    /// Time of the peak
    public var time: TimeInterval? {
        guard let sampleRate, sampleRate > 0 else { return nil }

        return Double(framePosition) / sampleRate
    }

    public var sampleRate: Double?

    /// Frame position of the peak
    public var framePosition: Int = 0

    /// Peak amplitude
    public var amplitude: Float = 1

    public init() {}

    public init(sampleRate: Double, framePosition: Int, amplitude: Float) {
        self.sampleRate = sampleRate
        self.framePosition = framePosition
        self.amplitude = amplitude
    }

    public init(url: URL) throws {
        let avfile = try AVAudioFile(forReading: url)

        guard let peak = avfile.peak else {
            throw NSError(description: "Couldn't open file at \(url.path)")
        }

        self = peak
    }
}
