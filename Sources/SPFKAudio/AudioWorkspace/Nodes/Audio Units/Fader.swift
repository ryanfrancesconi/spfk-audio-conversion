// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import SPFKAudioBase
import SPFKAudioC
import SPFKBase

extension Fader: EngineNode {
    public var inputNode: AVAudioNode? { avAudioNode }
    public var outputNode: AVAudioNode? { avAudioNode }

    public var isBypassed: Bool {
        get { avAudioNode.auAudioUnit.shouldBypassEffect }
        set { avAudioNode.auAudioUnit.shouldBypassEffect = newValue }
    }
}

/// Stereo Fader.
public class Fader: EngineNodeAU, TypeDescribable {
    public static let version: UInt32 = 1

    public private(set) var audioComponentDescription: AudioComponentDescription

    /// Underlying AVAudioNode
    public private(set) var avAudioNode: AVAudioNode

    // MARK: - Parameters

    /// Left Channel Amplification Factor
    @Parameter(FaderParameter.leftGain.parameterDef) public var leftGain: AUValue

    /// Right Channel Amplification Factor
    @Parameter(FaderParameter.rightGain.parameterDef) public var rightGain: AUValue

    /// Flip left and right signal
    @Parameter(FaderParameter.flipStereo.parameterDef) public var flipStereo: Bool

    /// Specification for whether to mix the stereo signal down to mono
    /// Make the output on left and right both be the same combination of incoming left and mixed equally
    @Parameter(FaderParameter.mixToMono.parameterDef) public var mixToMono: Bool

    /// Amplification Factor, from 0 ... x
    open var gain: AUValue = 1 {
        willSet {
            leftGain = newValue
            rightGain = newValue
        }
    }

    /// Amplification Factor in db
    public var dB: AUValue {
        get { gain.dBValue }
        set { gain = newValue.linearValue }
    }

    // MARK: - Initialization

    /// Initialize this fader node
    ///
    /// - Parameters:
    ///   - gain: Amplification factor (Default: 1, Minimum: 0)
    ///
    public init(gain: AUValue = 1) async throws {
        let subType = kAudioUnitFaderSubTypeString.fourCC ?? 0

        audioComponentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_MusicEffect,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Spongefork,
            componentFlags: AudioComponentFlags.sandboxSafe.rawValue,
            componentFlagsMask: 0
        )

        avAudioNode = try await AVAudioUnit.instantiateLocal(
            with: audioComponentDescription,
            named: Self.typeName,
            version: Self.version
        )

        setupParameters()

        leftGain = gain
        rightGain = gain
        flipStereo = false
        mixToMono = false
    }
}

public extension Fader {
    // MARK: - Automation

    /// Gain automation helper
    /// - Parameters:
    ///   - events: List of events
    ///   - startTime: start time
    func automate(events: [AutomationEvent], startTime: AVAudioTime) throws {
        try $leftGain.automate(events: events, startTime: startTime)
        try $rightGain.automate(events: events, startTime: startTime)
    }

    func automate(events: [AutomationEvent], offset: TimeInterval = 0) throws {
        try $leftGain.automate(events: events, offset: offset)
        try $rightGain.automate(events: events, offset: offset)
    }

    func ramp(from start: AUValue, to target: AUValue, duration: Float) {
        $leftGain.ramp(from: start, to: target, duration: duration)
        $rightGain.ramp(from: start, to: target, duration: duration)
    }

    func stopAutomation() throws {
        try $leftGain.stopAutomation()
        try $rightGain.stopAutomation()
    }
}
