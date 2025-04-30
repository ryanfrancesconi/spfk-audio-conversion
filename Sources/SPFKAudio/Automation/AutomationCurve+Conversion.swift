import AudioToolbox
import Foundation
import SPFKAudioC
import SPFKUtils

extension AutomationCurve {
    public static func createCurve(automationPoints: [AutomationPoint], resolution: Float = 0.2) -> [AutomationEvent] {
        // Log.debug(automationPoints)

        let points = Self.convertToTapered(automationPoints: automationPoints)

        guard points.isNotEmpty else { return [] }

        let curve = AutomationCurve(points: points)

        let value = curve.evaluate(initialValue: points[0].targetValue, resolution: resolution)

        return value
    }

    /// Convert our automation points to curve events
    /// - Returns: an array of ParameterAutomationPoint suitable for creating an AutomationCurve
    private static func convertToTapered(automationPoints: [AutomationPoint]) -> [ParameterAutomationPoint] {
        guard automationPoints.isNotEmpty else { return [] }

        // first convert the points to linear events
        let baseEvents = Self.linearEventsForCurve(automationPoints: automationPoints)

        var curvePoints = [ParameterAutomationPoint]()

        // The first point should have linear attributes
        var rampTaper: AUValue = LinearTaper.taper.in
        var rampSkew: AUValue = LinearTaper.skew.in

        for i in 0 ..< baseEvents.count {
            let event = baseEvents[i]

            // The taper values should be adjusted depending on if we're going up or down
            // otherwise you end up with reverse taper for down.
            if i > 0 {
                if baseEvents[i - 1].targetValue > event.targetValue {
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
    /// - Returns: an array of `AutomationEvent` suitable for passing to AutomationCurve
    private static func linearEventsForCurve(automationPoints: [AutomationPoint]) -> [AutomationEvent] {
        guard automationPoints.isNotEmpty else { return [] }

        let automationPoints = automationPoints.sorted()

        var events = [AutomationEvent]()

        for i in 0 ..< automationPoints.count {
            if i == 0 {
                // put slightly in past to trigger AUEventSampleTimeImmediate
                events.append(
                    AutomationEvent(
                        targetValue: automationPoints[i].gain,
                        startTime: automationPoints[i].time.float - 0.02,
                        rampDuration: 0.02
                    )
                )

            } else {
                let target = automationPoints[i].gain
                let rampDuration = automationPoints[i].time - automationPoints[i - 1].time
                let startTime = automationPoints[i - 1].time.float // + 0.02

                events.append(
                    AutomationEvent(
                        targetValue: target,
                        startTime: startTime,
                        rampDuration: rampDuration.float
                    )
                )
            }
        }

        return events
    }
}
