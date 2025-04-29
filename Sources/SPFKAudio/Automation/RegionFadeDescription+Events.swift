// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import OTCore
import SPFKAudioC

// NOTE: `AutomationEvent` is a SPFKAudioC C++ struct pulled from AudioKit

extension RegionFadeDescription {
    /// Generate an `AutomationEvent` curve from internal values
    ///
    /// - Returns: `AutomationEvent` curve
    public mutating func fadeInCurve() -> [AutomationEvent] {
        if let inEvents {
            return inEvents
        }

        // if no fade in, set to max
        guard inTime > 0 else {
            let events = [
                AutomationEvent(
                    targetValue: maximumGain,
                    startTime: -0.1,
                    rampDuration: 0
                ),
            ]

            inEvents = events
            return events
        }

        let rampDuration = inTime.float

        let curve = AutomationCurve(
            points: [
                ParameterAutomationPoint(
                    targetValue: maximumGain,
                    startTime: 0,
                    rampDuration: rampDuration,
                    rampTaper: inTaper,
                    rampSkew: inSkew
                ),
            ]
        )

        let initialValue: Float = RegionFadeDescription.minimumGain

        var events = [
            // put slightly in past to trigger AUEventSampleTimeImmediate
            AutomationEvent(
                targetValue: initialValue,
                startTime: -0.1,
                rampDuration: 0
            ),
        ]

        events += curve.evaluate(
            initialValue: initialValue,
            resolution: stepResolution(for: inTime)
        )

        inEvents = events

        return events
    }

    /// Generate a fade out curve for a region of audio
    ///
    /// - Parameters:
    ///   - segmentDuration: Total duration of the file segment. This is used to calculate
    ///   how far in advance the fade out should begin.
    ///   - sampleRateRatio: sample rate time ratio if needed
    /// - Returns: `AutomationEvent` curve
    public mutating func fadeOutCurve(
        segmentDuration: TimeInterval,
        sampleRateRatio: Float = 1
    ) -> [AutomationEvent] {
        if let outEvents {
            return outEvents
        }

        guard outTime > 0 else {
            outEvents = []
            return []
        }

        // when the start of the fade out should occur
        let timeTillFadeOut = Float(segmentDuration - outTime) / sampleRateRatio
        let rampDurationOut = outTime.float / sampleRateRatio

        let initialValue = maximumGain
        let isInsideCurve = timeTillFadeOut < 0

        var startTime = timeTillFadeOut.float

        // we're starting inside the curve so this will start immediately
        if isInsideCurve {
            startTime = 0
        }

        var events = [
            // put slightly in past to set initialValue
            AutomationEvent(
                targetValue: initialValue,
                startTime: startTime - 0.02,
                rampDuration: 0.02
            ),
        ]

        let curve = AutomationCurve(
            points: [
                ParameterAutomationPoint(
                    targetValue: RegionFadeDescription.minimumGain,
                    startTime: startTime,
                    rampDuration: rampDurationOut,
                    rampTaper: outTaper,
                    rampSkew: outSkew
                ),
            ]
        )

        events += curve.evaluate(
            initialValue: initialValue,
            resolution: stepResolution(for: outTime)
        )

        if isInsideCurve {
            events = adjustFadeout(events: events, timeTillFadeOut: timeTillFadeOut)
        }

        outEvents = events

        return events
    }
}

extension RegionFadeDescription {
    private func adjustFadeout(events: [AutomationEvent], timeTillFadeOut: Float) -> [AutomationEvent] {
        guard timeTillFadeOut < 0 else { return events }

        let startPoint = abs(timeTillFadeOut)

        let mappedEvents = events.map {
            AutomationEvent(
                targetValue: $0.targetValue,
                startTime: $0.startTime - startPoint,
                rampDuration: $0.rampDuration
            )
        }

        let pastEvents = mappedEvents.filter {
            $0.startTime < 0
        }.sorted {
            $0.startTime < $1.startTime
        }

        var futureEvents = mappedEvents.filter {
            $0.startTime >= 0
        }

        if let firstPast = pastEvents.last {
            // add the final negative event in past to set initialValue
            let immediate = AutomationEvent(
                targetValue: firstPast.targetValue,
                startTime: -0.02,
                rampDuration: 0.02
            )

            futureEvents.insert(immediate, at: 0)
        }

        return futureEvents
    }

    func stepResolution(for duration: TimeInterval) -> Float {
        var resolution = stepResolution

        let time = Float(duration)

        // make sure the resolution is low enough to have multiple points
        if time < resolution * 3 {
            resolution = time / 3
        }

        return resolution
    }
}
