// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Originally based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import Foundation
import SPFKAudioC
import SPFKUtils

/// An automation curve (with curved segments) suitable for any time varying parameter.
/// Includes functions for manipulating automation curves and conversion to linear automation ramps
/// used by DSP code.
public struct AutomationCurve: Equatable {
    /// Time between linear points to interpolate between
    public static let defaultResolution: Float = 0.2

    /// Array of points that make up the curve
    public var points: [ParameterAutomationPoint]

    public internal(set) var events: [AutomationEvent] = []

    /// Create a curve from a set of C points
    /// - Parameters:
    ///   - points: the automation points which already have a taper and skew assigned
    ///   - resolution: the resolution to interpolate between when creating curves
    public init(points: [ParameterAutomationPoint], resolution: Float = Self.defaultResolution) {
        self.points = points
        self.events = evaluate(resolution: resolution)
    }

    /// Create a curve from a set of UI points (and passed in taper) such as for track automation
    public init(
        automationPoints: [AutomationPoint],
        taper: AutomationTaper = .audio,
        resolution: Float = Self.defaultResolution
    ) {
        let points = Self.convertToTaperedSegment(automationPoints: automationPoints, taper: taper)
        self = AutomationCurve(points: points, resolution: resolution)
    }
}
