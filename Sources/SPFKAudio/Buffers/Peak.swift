import AVFoundation
import Foundation
import SPFKUtils

/// Local maximum containing the time, frame position and  amplitude
public struct Peak {
    internal static let min: Float = -10000.0

    /// Time of the peak
    public var time: TimeInterval = 0

    /// Frame position of the peak
    public var framePosition: Int = 0

    /// Peak amplitude
    public var amplitude: Float = 1

    public init() {}

    public init?(url: URL) {
        guard let avfile = try? AVAudioFile(forReading: url),
              let peak = avfile.peak else {
            Log.error("Couldn't open file at", url)
            return nil
        }

        self = peak
    }
}
