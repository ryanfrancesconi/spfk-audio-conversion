// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import SPFKAudioC

/// An object representing a fade in and out automation curves on a region of audio in a timeline
public struct RegionFadeDescription {
    /// a constant
    public static var minimumGain: AUValue = 0

    /// the value that the fade should fade to
    public var maximumGain: AUValue = 1

    public var stepResolution: Float = 0.2

    /// How long the fade in is
    public var inTime: TimeInterval = 0 {
        willSet {
            if newValue != inTime { fadeInCache = nil }
        }
    }

    public var inTaper: AUValue = AudioTaper.taper.in {
        willSet {
            if newValue != inTaper { fadeInCache = nil }
        }
    }

    /// the slope adjustment in the taper
    public var inSkew: AUValue = AudioTaper.skew.in

    /// How long the fade out is
    public var outTime: TimeInterval = 0 {
        willSet {
            if newValue != outTime { fadeOutCache = nil }
        }
    }

    public var outTaper: AUValue = AudioTaper.taper.out {
        willSet {
            if newValue != outTaper { fadeOutCache = nil }
        }
    }

    /// the slope adjustment in the taper
    public var outSkew: AUValue = AudioTaper.skew.out

    public var isFaded: Bool {
        inTime > 0 || outTime > 0
    }

    // MARK: Event cache

    var fadeInCache: AutomationCurve?
    var fadeOutCache: AutomationCurve?

    public init() {}
}
