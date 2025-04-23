// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import SPFKAudioC

// `AutomationEvent` is a C++ struct

extension FadeDescription {
    /// Convenience function for generating an `AutomationEvent` curve from struct values
    /// - Returns: `AutomationEvent` curve
    public func fadeInCurve() -> [AutomationEvent] {
        // if no fade in, set to max
        guard inTime > 0 else {
            return [AutomationEvent(targetValue: maximumGain,
                                    startTime: -0.1,
                                    rampDuration: 0)]
        }

        let rampDuration = inTime.float
        let initialValue: Float = FadeDescription.minimumGain
        let startTime: Float = 0

        let curve = AutomationCurve(points: [
            ParameterAutomationPoint(targetValue: maximumGain,
                                     startTime: startTime,
                                     rampDuration: rampDuration,
                                     rampTaper: inTaper,
                                     rampSkew: inSkew),
        ])

        var events = [
            // put slightly in past to trigger AUEventSampleTimeImmediate
            AutomationEvent(targetValue: initialValue,
                            startTime: startTime - 0.1,
                            rampDuration: 0),
        ]

        var resolution: Float = 0.2

        // make sure the resolution is low enough to have multiple points
        if inTime.float < resolution * 3 {
            resolution = inTime.float / 3
        }

        // Log.debug("inTime", inTime, "resolution", resolution)

        events += curve.evaluate(initialValue: initialValue, resolution: resolution)

        return events
    }

    /// Convenience function for generation a fade out curve
    /// - Parameters:
    ///   - duration: total duration of the file segment
    ///   - rate: playback rate
    ///   - timeRatio: sample rate time ratio if needed
    /// - Returns: `AutomationEvent` curve
    public func fadeOutCurve(duration: TimeInterval, rate: AUValue = 1, timeRatio: Float = 1) -> [AutomationEvent] {
        guard outTime > 0 else {
            return []
        }

        var playerEditedDuration = duration

        // adjust for the playback rate so it's in real time
        playerEditedDuration /= rate.double

        // when the start of the fade out should occur
        let timeTillFadeOut = Float(playerEditedDuration - outTime) / timeRatio
        let rampDurationOut = outTime.float / timeRatio
        var startTime = timeTillFadeOut.float
        var adjustedRampDuration = rampDurationOut
        var initialValue = maximumGain

        // we're starting inside the curve
        if startTime < 0 {
            adjustedRampDuration += startTime
            startTime = 0
            // how far into the curve we're starting
            let skewRatio: Float = adjustedRampDuration / rampDurationOut
            initialValue *= skewRatio
        }

        var events = [
            // put slightly in past to set initialValue
            AutomationEvent(targetValue: initialValue,
                            startTime: startTime - 0.02,
                            rampDuration: 0.02),
        ]

        let curve = AutomationCurve(points: [
            ParameterAutomationPoint(targetValue: FadeDescription.minimumGain,
                                     startTime: startTime,
                                     rampDuration: adjustedRampDuration,
                                     rampTaper: outTaper,
                                     rampSkew: outSkew),
        ])

        var resolution: Float = 0.2

        // make sure the resolution is low enough to have multiple points
        if outTime.float < resolution * 3 {
            resolution = outTime.float / 3
        }
        
        events += curve.evaluate(initialValue: initialValue, resolution: resolution)

        // Log.debug(events)

        return events
    }
}
