import AudioToolbox
import Foundation
import SPFKAudioC
import SPFKUtils

extension AutomationCurve {
    /// Convert our automation points to curve events
    /// - Returns: an array of ParameterAutomationPoint suitable for creating an AutomationCurve
    static func convertToTaperedSegment(automationPoints: [AutomationPoint]) -> [ParameterAutomationPoint] {
        guard automationPoints.isNotEmpty else { return [] }

        // first convert the points to linear events
        let baseEvents = Self.convertToEvent(automationPoints: automationPoints)

        var curvePoints = [ParameterAutomationPoint]()

        // The first point should have linear attributes
        var rampTaper: AUValue = LinearTaper.taper.in
        var rampSkew: AUValue = LinearTaper.skew.in

        for i in 0 ..< baseEvents.count {
            let event = baseEvents[i]

            // The taper values should be adjusted depending on if we're going up or down
            // otherwise you end up with reverse taper for down.
            if i > 0 {
                let isDown = baseEvents[i - 1].targetValue > event.targetValue

                if isDown {
                    // going down
                    rampTaper = AudioTaper.taper.out
                    rampSkew = AudioTaper.skew.out

                } else {
                    // going up
                    rampTaper = AudioTaper.taper.in
                    rampSkew = AudioTaper.skew.in
                }
            }

            let point = ParameterAutomationPoint(
                targetValue: event.targetValue,
                startTime: event.startTime,
                rampDuration: event.rampDuration,
                rampTaper: rampTaper,
                rampSkew: rampSkew
            )

            curvePoints.append(point)
        }

        return curvePoints
    }

    /// Translate a set of AutomationPoints to AutomationEvents
    /// - Parameter automationPoints: the points to convert
    /// - Returns: an array of `AutomationEvent` suitable for passing to the AudioUnit
    private static func convertToEvent(automationPoints: [AutomationPoint]) -> [AutomationEvent] {
        guard automationPoints.isNotEmpty else { return [] }

        let automationPoints = automationPoints.sorted()

        var events: [AutomationEvent] = [
            // put slightly in past to trigger AUEventSampleTimeImmediate
            AutomationEvent(
                targetValue: automationPoints[0].gain,
                startTime: automationPoints[0].time.float - 0.02,
                rampDuration: 0.02
            ),
        ]

        guard automationPoints.count > 1 else {
            return events
        }

        for i in 1 ..< automationPoints.count {
            let targetValue = automationPoints[i].gain

            // start at the previous point
            let startTime = automationPoints[i - 1].time.float

            // and ramp this long
            let rampDuration = automationPoints[i].time - automationPoints[i - 1].time

            events.append(
                AutomationEvent(
                    targetValue: targetValue,
                    startTime: startTime,
                    rampDuration: rampDuration.float
                )
            )
        }

        return events
    }
}
