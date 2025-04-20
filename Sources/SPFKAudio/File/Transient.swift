// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation

/// Local maximum containing the time, frame position and  amplitude
public struct Transient: Comparable {
    public static func > (lhs: Self, rhs: Self) -> Bool {
        lhs.amplitude > rhs.amplitude
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.amplitude < rhs.amplitude
    }

    // variable with very small value to detect the peak value against
    internal static let min: Float = -10000.0

    /// General dB range shared across a number of components
    public static let dBRange: ClosedRange<AUValue> = -60 ... 0

    /// Time of the peak
    public var time: Double

    /// Peak amplitude
    public var amplitude: Float {
        didSet {
            dBValue = amplitude.dBValue
        }
    }

    /// Sample position of the peak
    public var position: AVAudioFramePosition

    public private(set) var dBValue: Float

    public private(set) var passesThreshold: Bool = false

    public init(time: TimeInterval = 0, amplitude: Float = 0, position: AVAudioFramePosition = 0, passesThreshold: Bool = false) {
        self.time = time
        self.amplitude = amplitude
        dBValue = amplitude.dBValue
        self.position = position
        self.passesThreshold = passesThreshold
    }
}

extension Transient {
    public struct Element {
        public var inPoint: TimeInterval
        public var outPoint: TimeInterval
        public var syncPoint: TimeInterval?
    }

    public struct ElementData {
        public var elements: [Element]
        public var transientCollection: TransientCollection
    }

    public struct IndexedAmplitude {
        public var amplitude: Float
        public var index: Int
        public private(set) var dBValue: Float

        public init(amplitude: Float, index: Int) {
            self.amplitude = amplitude
            self.index = index
            dBValue = amplitude.dBValue
        }
    }
}
