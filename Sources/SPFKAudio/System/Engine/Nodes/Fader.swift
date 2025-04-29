// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import SPFKAudioC
import SPFKUtils

extension Fader: EngineNode {
    public var inputNode: AVAudioNode? { avAudioNode }
    public var outputNode: AVAudioNode? { avAudioNode }

    public var isBypassed: Bool {
        get { avAudioNode.auAudioUnit.shouldBypassEffect }
        set { avAudioNode.auAudioUnit.shouldBypassEffect = newValue }
    }

    public func detach() throws {
        try detachNodes()
    }
}

/// Stereo Fader.
public class Fader: EngineNodeAU, TypeDescribable {
    public static let subType = fourCC("fder")

    public static let audioComponentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_MusicEffect,
        componentSubType: Fader.subType,
        componentManufacturer: kAudioUnitManufacturer_Spongefork,
        componentFlags: AudioComponentFlags.sandboxSafe.rawValue,
        componentFlagsMask: 0
    )

    /// Underlying AVAudioNode
    public private(set) var avAudioNode: AVAudioNode

    // MARK: - Parameters

    /// Amplification Factor, from 0 ... x
    open var gain: AUValue = 1 {
        willSet {
            leftGain = newValue
            rightGain = newValue
        }
    }

    /// Gain can be any non-negative number -- however 0 - 4 is
    /// a practical range: 0 ... +12dB
    public static let defaultGainRange: ClosedRange<AUValue> = 0 ... 4

    /// Specification details for left gain
    public static let leftGainDef = NodeParameterDef(
        identifier: "leftGain",
        name: "Left Gain",
        address: akGetParameterAddress("FaderParameterLeftGain"),
        defaultValue: 1,
        range: Fader.defaultGainRange,
        unit: .linearGain)

    /// Left Channel Amplification Factor
    @Parameter(leftGainDef) public var leftGain: AUValue

    /// Specification details for right gain
    public static let rightGainDef = NodeParameterDef(
        identifier: "rightGain",
        name: "Right Gain",
        address: akGetParameterAddress("FaderParameterRightGain"),
        defaultValue: 1,
        range: Fader.defaultGainRange,
        unit: .linearGain)

    /// Right Channel Amplification Factor
    @Parameter(rightGainDef) public var rightGain: AUValue

    /// Amplification Factor in db
    public var dB: AUValue {
        get { gain.dBValue }
        set { gain = newValue.linearValue }
    }

    /// Whether or not to flip left and right channels
    public static let flipStereoDef = NodeParameterDef(
        identifier: "flipStereo",
        name: "Flip Stereo",
        address: akGetParameterAddress("FaderParameterFlipStereo"),
        defaultValue: 0,
        range: 0.0 ... 1.0,
        unit: .boolean)

    /// Flip left and right signal
    @Parameter(flipStereoDef) public var flipStereo: Bool

    /// Specification for whether to mix the stereo signal down to mono
    public static let mixToMonoDef = NodeParameterDef(
        identifier: "mixToMono",
        name: "Mix To Mono",
        address: akGetParameterAddress("FaderParameterMixToMono"),
        defaultValue: 0,
        range: 0.0 ... 1.0,
        unit: .boolean)

    /// Make the output on left and right both be the same combination of incoming left and mixed equally
    @Parameter(mixToMonoDef) public var mixToMono: Bool

    // MARK: - Initialization

    /// Initialize this fader node
    ///
    /// - Parameters:
    ///   - gain: Amplification factor (Default: 1, Minimum: 0)
    ///
    public init(gain: AUValue = 1) async throws {
        avAudioNode = try await AVAudioUnit.instantiateLocal(
            componentDescription: Self.audioComponentDescription,
            named: Fader.typeName
        )

        setupParameters()

        leftGain = gain
        rightGain = gain
        flipStereo = false
        mixToMono = false
    }
}

extension Fader {
    // MARK: - Automation

    /// Gain automation helper
    /// - Parameters:
    ///   - events: List of events
    ///   - startTime: start time
    public func automateGain(events: [AutomationEvent], startTime: AVAudioTime) {
        $leftGain.automate(events: events, startTime: startTime)
        $rightGain.automate(events: events, startTime: startTime)
    }

    public func automateGain(events: [AutomationEvent], offset: TimeInterval = 0) {
        $leftGain.automate(events: events, offset: offset)
        $rightGain.automate(events: events, offset: offset)
    }

    public func ramp(from start: AUValue, to target: AUValue, duration: Float) {
        $leftGain.ramp(from: start, to: target, duration: duration)
        $rightGain.ramp(from: start, to: target, duration: duration)
    }

    /// Tapered Ramp from a source value (which is ramped to over 20ms) to a target value
    ///
    /// - Parameters:
    ///   - start: initial value
    ///   - target: destination value
    ///   - duration: duration to ramp to the target value in seconds
    ///   - rampTaper: Taper, default is 3 for fade in, 1/3 for fade out
    ///   - rampSkew: Skew, default is 1/3 for fade in, and 3 for fade out
    ///   - resolution: Segment duration, default 20ms
    public func taperedRamp(
        from start: AUValue,
        to target: AUValue,
        duration: AUValue,
        rampTaper: AUValue = AudioTaper.taper.in,
        rampSkew: AUValue = AudioTaper.skew.in,
        resolution: AUValue = 0.02,
        startTime scheduledTime: AVAudioTime? = nil
    ) {
        stopAutomation()

        let startTime: AUValue = 0.02
        var rampTaper = rampTaper
        var rampSkew = rampSkew

        if target < start {
            rampTaper = 1 / rampTaper
            rampSkew = 1 / rampSkew
        }

        // this ensures we get a AUEventSampleTimeImmediate set to the start value
        let setupEvents = [
            AutomationEvent(targetValue: start, startTime: 0, rampDuration: 0),
            AutomationEvent(targetValue: start, startTime: startTime + 0.01, rampDuration: 0.01),
        ]

        let points = [
            ParameterAutomationPoint(
                targetValue: start,
                startTime: startTime + 0.02,
                rampDuration: 0.02,
                rampTaper: rampTaper,
                rampSkew: rampSkew
            ),

            ParameterAutomationPoint(
                targetValue: target,
                startTime: startTime + 0.04,
                rampDuration: duration - 0.04,
                rampTaper: rampTaper,
                rampSkew: rampSkew
            ),
        ]

        let curve = AutomationCurve(points: points)
        let events = setupEvents + curve.evaluate(
            initialValue: start,
            resolution: resolution
        )

        $leftGain.automate(events: events, startTime: scheduledTime)
        $rightGain.automate(events: events, startTime: scheduledTime)
    }

    /// Stop automation
    public func stopAutomation() {
        $leftGain.stopAutomation()
        $rightGain.stopAutomation()
    }
}
