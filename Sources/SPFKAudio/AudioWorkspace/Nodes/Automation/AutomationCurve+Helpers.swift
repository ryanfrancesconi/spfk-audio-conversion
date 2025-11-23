// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Originally based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AudioToolbox
import Foundation
import SPFKAudioC
import SPFKBase

// MARK: - create curve

extension AutomationCurve {
    /// Returns a new piecewise-linear automation curve which can be handed off to the audio thread
    /// for efficient processing.
    ///
    /// - Parameters:
    ///   - initialValue: Starting point
    ///   - resolution: Duration of each linear segment in seconds
    ///
    /// - Returns: A new array of piecewise linear automation points
    func evaluate(resolution: Float) -> [AutomationEvent] {
        guard points.isNotEmpty else { return [] }

        var result = [AutomationEvent]()

        // The last evaluated value, updated during the loop
        var currentValue = points[0].targetValue

        for i in 0 ..< points.count {
            do {
                result += try curveTo(
                    index: i,
                    currentValue: currentValue,
                    resolution: resolution
                )

                if let lastValue = result.last?.targetValue {
                    currentValue = lastValue
                }

            } catch {
                Log.error(error)
            }
        }

        return result
    }

    private func curveTo(index i: Int, currentValue: Float, resolution: Float) throws -> [AutomationEvent] {
        guard points.indices.contains(i) else {
            throw NSError(description: "index \(i) is out of bounds")
        }

        let point = points[i]

        guard !point.isLinear() else {
            return [
                AutomationEvent(
                    targetValue: point.targetValue,
                    startTime: point.startTime,
                    rampDuration: point.rampDuration
                ),
            ]
        }

        var rampDuration = resolution
        var currentValue = currentValue
        var result = [AutomationEvent]()

        // Cut off the end if another point comes along.
        let nextPointStart: Float = i < points.count - 1 ?
            points[i + 1].startTime :
            .greatestFiniteMagnitude

        let endTime: Float = min(
            nextPointStart,
            point.startTime + point.rampDuration
        )

        var position = point.startTime
        let startValue = currentValue

        // March position along the segment
        // this is effectively `while position <= endTime - resolution` without potentional for rounding errors
        let eventCount = round(endTime / rampDuration).int

        for _ in 0 ..< eventCount {
            let isLastPoint = position + rampDuration >= endTime

            if isLastPoint {
                // if the time + resolution is past the endTime, truncate it to end exactly at endTime
                rampDuration = endTime - position
            }

            currentValue = Self.evalRamp(
                start: startValue,
                point: point,
                time: position + rampDuration,
                endTime: point.startTime + point.rampDuration
            )

            result.append(
                AutomationEvent(
                    targetValue: currentValue,
                    startTime: position,
                    rampDuration: rampDuration
                )
            )

            position += rampDuration

            // final point should always end exactly at endTime
            // safety check to not run past the final target value
            guard position < endTime else {
                break
            }
        }

        return result
    }
}

extension AutomationCurve {
    static func evalRamp(start: Float, point: ParameterAutomationPoint, time: Float, endTime: Float) -> Float {
        let remain = endTime - time
        let taper = point.rampTaper
        let goal = point.targetValue

        // x is normalized position in ramp segment
        let x = (point.rampDuration - remain) / point.rampDuration
        let taper1 = start + (goal - start) * pow(x, abs(taper))
        let absxm1 = abs((point.rampDuration - remain) / point.rampDuration - 1.0)
        let taper2 = start + (goal - start) * (1.0 - pow(absxm1, 1.0 / abs(taper)))

        return taper1 * (1.0 - point.rampSkew) + taper2 * point.rampSkew
    }

    /// Convert our automation points to curve events
    /// - Returns: an array of ParameterAutomationPoint suitable for creating an AutomationCurve
    static func convertToTaperedSegment(
        automationPoints: [AutomationPoint],
        taper: AudioTaper
    ) -> [ParameterAutomationPoint] {
        guard automationPoints.isNotEmpty else { return [] }

        // first convert the points to linear events
        let baseEvents = Self.convertToLinearEvents(automationPoints: automationPoints)

        var curvePoints = [ParameterAutomationPoint]()

        // The first point should have linear attributes
        var rampTaper: AUValue = AudioTaper.linear.value
        var rampSkew: AUValue = AudioTaper.linear.skew

        for i in 0 ..< baseEvents.count {
            let event = baseEvents[i]

            if i > 0 {
                // The taper values should be adjusted depending on if we're going up or down
                // otherwise you end up with reverse taper for down.
                let isDown = baseEvents[i - 1].targetValue > event.targetValue
                rampTaper = isDown ? taper.inverseValue : taper.value
                rampSkew = taper.skew
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
    private static func convertToLinearEvents(automationPoints: [AutomationPoint]) -> [AutomationEvent] {
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
