// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio
// Originally based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import Foundation
import SPFKAudioC
import SPFKBase

// MARK: - edit

extension AutomationCurve {
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
                rampDuration: $0.rampDuration,
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

        guard pastEvents.isNotEmpty, futureEvents.isNotEmpty else {
            throw NSError(description: "Failed to crop events")
        }

        if let firstPast = pastEvents.last {
            // add the final negative start event in past to set initialValue
            let immediate = AutomationEvent(
                targetValue: firstPast.targetValue,
                startTime: -0.02,
                rampDuration: 0.02,
            )

            futureEvents.insert(immediate, at: 0)
        }

        events = futureEvents
    }
}
