// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import Foundation
import SPFKAudioC
import SPFKUtils

/// An automation curve (with curved segments) suitable for any time varying parameter.
/// Includes functions for manipulating automation curves and conversion to linear automation ramps
/// used by DSP code.
public struct AutomationCurve {
    /// Array of points that make up the curve
    public var points: [ParameterAutomationPoint]

    public private(set) var events: [AutomationEvent] = []

    /// Initialize with points
    /// - Parameter points: Array of points
    public init(points: [ParameterAutomationPoint], resolution: Float = 0.2) {
        self.points = points
        self.events = evaluate(resolution: resolution)
    }

    public init(automationPoints: [AutomationPoint], resolution: Float = 0.2) {
        let points = Self.convertToTaperedSegment(automationPoints: automationPoints)
        self = AutomationCurve(points: points, resolution: resolution)
    }
}

extension AutomationCurve {
    /// Returns a new piecewise-linear automation curve which can be handed off to the audio thread
    /// for efficient processing.
    ///
    /// - Parameters:
    ///   - initialValue: Starting point
    ///   - resolution: Duration of each linear segment in seconds
    ///
    /// - Returns: A new array of piecewise linear automation points
    private func evaluate(resolution: Float = 0.2) -> [AutomationEvent] {
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

        var resolution = resolution
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
        let eventCount = round(endTime / resolution).int

        for _ in 0 ..< eventCount {
            let isLastPoint = position + resolution >= endTime

            if isLastPoint {
                // if the time + resolution is past the endTime, truncate it to end exactly at endTime
                resolution = endTime - position
            }

            currentValue = Self.evalRamp(
                start: startValue,
                point: point,
                time: position + resolution,
                endTime: point.startTime + point.rampDuration
            )

            result.append(
                AutomationEvent(
                    targetValue: currentValue,
                    startTime: position,
                    rampDuration: resolution
                )
            )

            position += resolution

            // final point should always end exactly at endTime
            // safety check to not run past the final target value
            guard position < endTime else {
                break
            }
        }

        return result
    }

    /// Replaces automation over a time range.
    ///
    /// Use this when calculating a new automation curve after recording automation.
    ///
    /// - Parameters:
    ///   - range: time range
    ///   - withPoints: new automation events
    /// - Returns: new automation curve
    public func replace(range: ClosedRange<Float>, withPoints newPoints: [(Float, AUValue)]) -> AutomationCurve {
        var result = points
        let startTime = range.lowerBound
        let stopTime = range.upperBound

        // Clear existing points in segment range.
        result.removeAll { point in
            point.startTime >= startTime && point.startTime <= stopTime
        }

        // Append recorded points.
        result.append(contentsOf: newPoints.map { point in
            ParameterAutomationPoint(targetValue: point.1, startTime: point.0, rampDuration: 0.01)
        })

        // Sort vector by time.
        result.sort { $0.startTime < $1.startTime }

        return AutomationCurve(points: result)
    }

    public mutating func crop(after startPoint: Float) throws {
        guard events.isNotEmpty else {
            throw NSError(description: "No events to crop")
        }

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

        guard pastEvents.isNotEmpty && futureEvents.isNotEmpty else {
            throw NSError(description: "Failed to crop events")
        }

        if let firstPast = pastEvents.last {
            // add the final negative start event in past to set initialValue
            let immediate = AutomationEvent(
                targetValue: firstPast.targetValue,
                startTime: -0.02,
                rampDuration: 0.02
            )

            futureEvents.insert(immediate, at: 0)
        }

        self.events = futureEvents
    }
}

extension AutomationCurve {
    fileprivate static func evalRamp(start: Float, point: ParameterAutomationPoint, time: Float, endTime: Float) -> Float {
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
}
