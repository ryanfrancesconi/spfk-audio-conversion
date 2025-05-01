// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import OTCore
import SPFKAudioC
import SPFKUtils

// NOTE: `AutomationEvent` is a SPFKAudioC C++ struct pulled from AudioKit

extension RegionFadeDescription {
    /// Generate an `AutomationEvent` curve from internal values
    ///
    /// - Returns: `AutomationCurve`
    public mutating func fadeInCurve() -> AutomationCurve? {
        // if no fade in, set to max
        guard inTime > 0 else {
            fadeInCache = nil
            return nil
        }

        if let fadeInCache {
            return fadeInCache
        }

        let rampDuration = inTime.float

        let points = [
            ParameterAutomationPoint(
                targetValue: Self.minimumGain,
                startTime: -0.1,
                rampDuration: 0,
                rampTaper: LinearTaper.taper.in,
                rampSkew: LinearTaper.skew.in
            ),

            ParameterAutomationPoint(
                targetValue: maximumGain,
                startTime: 0,
                rampDuration: rampDuration,
                rampTaper: inTaper,
                rampSkew: inSkew
            ),
        ]

        let curve = AutomationCurve(points: points, resolution: stepResolution(for: inTime))

        fadeInCache = curve

        return curve
    }

    /// Generate a fade out curve for a region of audio
    ///
    /// - Parameters:
    ///   - segmentDuration: Total duration of the file segment. This is used to calculate
    ///   how far in advance the fade out should begin.
    ///
    ///   - sampleRateRatio: sample rate time ratio if needed
    ///
    /// - Returns: `AutomationCurve`
    public mutating func fadeOutCurve(
        segmentDuration: TimeInterval,
        sampleRateRatio: Float = 1
    ) -> AutomationCurve? {
        guard outTime > 0 else {
            fadeOutCache = nil
            return nil
        }

        if let fadeOutCache {
            return fadeOutCache
        }

        let rampDuration = outTime.float / sampleRateRatio

        // offset: when the start of the fade out should occur. If it is negative, playback is starting inside the curve.
        // in that case segmentDuration is < outTime
        let offset = Float(segmentDuration - outTime) / sampleRateRatio
        let isInsideCurve = offset < 0
        let startTime = max(0, offset.float)

        let points = [
            ParameterAutomationPoint(
                targetValue: maximumGain,
                startTime: startTime - 0.02,
                rampDuration: 0.02,
                rampTaper: LinearTaper.taper.out,
                rampSkew: LinearTaper.skew.out
            ),

            ParameterAutomationPoint(
                targetValue: Self.minimumGain,
                startTime: startTime,
                rampDuration: rampDuration,
                rampTaper: outTaper,
                rampSkew: outSkew
            ),
        ]

        var curve = AutomationCurve(points: points, resolution: stepResolution(for: outTime))

        if isInsideCurve {
            do {
                try curve.crop(after: abs(offset))
            } catch {
                Log.error(error)
            }
        }

        fadeOutCache = curve // cache

        return curve
    }
}

extension RegionFadeDescription {
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
