// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import OTCore
import SPFKAudioC

// `AutomationEvent` is a SPFKAudioC C++ struct

extension RegionFadeDescription {
    /// Convenience function for generating an `AutomationEvent` curve from struct values
    /// - Returns: `AutomationEvent` curve
    public mutating func fadeInCurve() -> [AutomationEvent] {
        if let inEvents {
            return inEvents
        }

        // if no fade in, set to max
        guard inTime > 0 else {
            let events = [
                AutomationEvent(targetValue: maximumGain,
                                startTime: -0.1,
                                rampDuration: 0),
            ]

            inEvents = events
            return events
        }

        let rampDuration = inTime.float
        let initialValue: Float = RegionFadeDescription.minimumGain
        let startTime: Float = 0

        let curve = AutomationCurve(points: [
            ParameterAutomationPoint(
                targetValue: maximumGain,
                startTime: startTime,
                rampDuration: rampDuration,
                rampTaper: inTaper,
                rampSkew: inSkew
            ),
        ])

        var events = [
            // put slightly in past to trigger AUEventSampleTimeImmediate
            AutomationEvent(targetValue: initialValue,
                            startTime: startTime - 0.1,
                            rampDuration: 0),
        ]

        var resolution = stepResolution

        // make sure the resolution is low enough to have multiple points
        if inTime.float < resolution * 3 {
            resolution = inTime.float / 3
        }

        events += curve.evaluate(initialValue: initialValue, resolution: resolution)

        inEvents = events

        return events
    }

    /// Convenience function for generation a fade out curve
    /// - Parameters:
    ///   - duration: total duration of the file segment
    ///   - rate: playback rate
    ///   - timeRatio: sample rate time ratio if needed
    /// - Returns: `AutomationEvent` curve
    public mutating func fadeOutCurve(duration: TimeInterval, rate: AUValue = 1, timeRatio: Float = 1) -> [AutomationEvent] {
        if let outEvents {
            return outEvents
        }

        guard outTime > 0 else {
            outEvents = []
            return []
        }

        var playerEditedDuration = duration

        // adjust for the playback rate so it's in real time
        // TODO: the duration could alrady be divided by the rate when this function is called to eliminate that variable
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

            // TODO: fix, this is actually linear approximate
            // how far into the curve we're starting
            let skewRatio: Float = adjustedRampDuration / rampDurationOut
            initialValue *= skewRatio
        }

        var events = [
            // put slightly in past to set initialValue
            AutomationEvent(
                targetValue: initialValue,
                startTime: startTime - 0.02,
                rampDuration: 0.02
            ),
        ]

        let curve = AutomationCurve(points: [
            ParameterAutomationPoint(
                targetValue: RegionFadeDescription.minimumGain,
                startTime: startTime,
                rampDuration: adjustedRampDuration,
                rampTaper: outTaper,
                rampSkew: outSkew
            ),
        ])

        var resolution = stepResolution

        // make sure the resolution is low enough to have multiple points
        if outTime.float < resolution * 3 {
            resolution = outTime.float / 3
        }

        events += curve.evaluate(initialValue: initialValue, resolution: resolution)

        outEvents = events

        return events
    }
}
