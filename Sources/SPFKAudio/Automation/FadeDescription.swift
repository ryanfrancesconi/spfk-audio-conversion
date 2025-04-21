// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import SPFKAudioC

public struct FadeDescription {
    public init() {}

    public enum Linear {
        // a few presets for lack of a better place to put them at the moment
        public static var taper = (in: AUValue(1.0), out: AUValue(1.0))
        public static var skew = (in: AUValue(0), out: AUValue(0))
    }

    public enum AudioTaper {
        // half pipe
        public static var taper = (in: AUValue(3.0), out: AUValue(0.333))
        public static var skew = (in: AUValue(0.333), out: AUValue(1))
    }

    public enum ReverseAudioTaper {
        // flipped half pipe
        public static var taper = (in: AUValue(0.333), out: AUValue(3.0))
        public static var skew = (in: AUValue(1), out: AUValue(0.333))
    }

    /// a constant
    public static var minimumGain: AUValue = 0

    /// the value that the fader should fade to, settable
    public var maximumGain: AUValue = 1

    // In properties
    public var inTime: TimeInterval = 0 {
        willSet {
            if newValue != inTime { needsUpdate = true }
        }
    }

    public var inTaper: AUValue = AudioTaper.taper.in {
        willSet {
            if newValue != inTaper { needsUpdate = true }
        }
    }

    // the slope adjustment in the taper
    public var inSkew: AUValue = AudioTaper.skew.in

    // Out properties
    public var outTime: TimeInterval = 0 {
        willSet {
            if newValue != outTime { needsUpdate = true }
        }
    }

    public var outTaper: AUValue = AudioTaper.taper.out {
        willSet {
            if newValue != outTaper { needsUpdate = true }
        }
    }

    // the slope adjustment in the taper
    public var outSkew: AUValue = 1

    // the needsUpdate flag is used by the buffering scheme
    // and the cache
    public var needsUpdate: Bool = false {
        didSet {
            // clear the fade cache so it will be regenerated with the new values
            cache = nil
        }
    }

    public var isFaded: Bool {
        inTime > 0 || outTime > 0
    }

    public var cache: [AutomationEvent]?
}
