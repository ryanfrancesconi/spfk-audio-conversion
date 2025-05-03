// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import SPFKUtils
import SPFKAudioC

/// An object representing a fade in and out automation curves on a region of audio in a timeline
public struct RegionFadeDescription {
    /// a constant, 0
    public static let minimumGain: AUValue = 0

    /// the value that the fade should fade to
    public var maximumGain: AUValue = 1

    public var stepResolution: Float = 0.2 {
        willSet {
            if newValue != stepResolution {
                fadeInCache = nil
                fadeOutCache = nil
            }
        }
    }

    /// How long the fade in is
    public var inTime: TimeInterval = 0 {
        willSet {
            if newValue != inTime { fadeInCache = nil }
        }
    }

    /// How long the fade out is
    public var outTime: TimeInterval = 0 {
        willSet {
            if newValue != outTime { fadeOutCache = nil }
        }
    }
    
    
    public var segmentDuration: TimeInterval = 0 {
        willSet {
            if newValue != segmentDuration { fadeOutCache = nil }
        }
    }
    
    public var taper = AutomationTaper.audio {
        willSet {
            if newValue.taperUp != taper.taperUp {
                fadeInCache = nil
            }

            if newValue.taperDown != taper.taperDown {
                fadeOutCache = nil
            }
        }
    }

    public var sampleRateRatio: Float = 1 {
        willSet {
            if newValue != sampleRateRatio { fadeOutCache = nil }
        }
    }

    public var isFaded: Bool {
        inTime > 0 || outTime > 0
    }

    // MARK: Event cache

    var fadeInCache: AutomationCurve?
    var fadeOutCache: AutomationCurve?

    public init() {}
}
