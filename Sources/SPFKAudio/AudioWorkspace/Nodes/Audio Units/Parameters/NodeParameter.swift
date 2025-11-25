// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import SPFKAudioBase
import SPFKBase

/// NodeParameter wraps AUParameter in a user-friendly interface and adds some AudioKit-specific functionality.
public class NodeParameter {
    // force unwrapped is bad
    public private(set) var avAudioNode: AVAudioNode?

    /// AU Parameter that this wraps
    public private(set) var parameter: AUParameter!

    // MARK: Parameter properties

    /// Value of the parameter
    public var value: AUValue {
        get { parameter.value }
        set {
            if let avAudioUnit = avAudioNode as? AVAudioUnit {
                AudioUnitSetParameter(
                    avAudioUnit.audioUnit,
                    param: AudioUnitParameterID(def.address),
                    to: newValue.clamped(to: range)
                )
            }

            parameter.value = newValue.clamped(to: range)
        }
    }

    /// Boolean values for parameters
    public var boolValue: Bool {
        get { value > 0.5 }
        set { value = newValue ? 1.0 : 0.0 }
    }

    /// Minimum value
    public var minValue: AUValue {
        parameter.minValue
    }

    /// Maximum value
    public var maxValue: AUValue {
        parameter.maxValue
    }

    /// Value range
    public var range: ClosedRange<AUValue> {
        parameter.minValue ... parameter.maxValue
    }

    public var sampleRate: Double {
        avAudioNode?.outputFormat(forBus: 0).sampleRate ??
            AudioDefaults.shared.unsafeSystemFormat.sampleRate
    }

    public var def: NodeParameterDef

    /// Init with definition
    /// - Parameter def: Node parameter definition
    public init(_ def: NodeParameterDef) {
        self.def = def
    }

    // MARK: Lifecycle

    /// Helper function to attach the parameter to the appropriate tree
    /// - Parameters:
    ///   - avAudioNode: AVAudioUnit to associate with
    public func associate(with avAudioNode: AVAudioNode) throws {
        self.avAudioNode = avAudioNode

        guard let tree = avAudioNode.auAudioUnit.parameterTree else {
            throw NSError(description: "No parameter tree found for \(avAudioNode).")
        }

        parameter = tree.parameter(withAddress: def.address)

        guard parameter != nil else {
            throw NSError(description: "Failed to find parameter at address \(def.address)")
        }
    }

    /// Helper function to attach the parameter to the appropriate tree
    /// - Parameters:
    ///   - avAudioNode: AVAudioUnit to associate with
    ///   - parameter: Parameter to associate
    public func associate(with avAudioNode: AVAudioNode, parameter: AUParameter) {
        self.avAudioNode = avAudioNode
        self.parameter = parameter
    }

    // MARK: Automation

    public var renderObserverToken: Int?

    /// Automate to a new value using a ramp.
    public func ramp(to value: AUValue, duration: Float, delay: Float = 0, sampleRate: Float) {
        var delaySamples = AUAudioFrameCount(delay * sampleRate)

        if delaySamples > 4096 {
            Log.error("Warning: delay longer than 4096, setting to to 4096")
            delaySamples = 4096
        }

        if !parameter.flags.contains(.flag_CanRamp) {
            Log.error("Error: can't ramp parameter \(parameter.displayName)")
            return
        }

        let paramBlock = avAudioNode?.auAudioUnit.scheduleParameterBlock

        paramBlock?(
            AUEventSampleTimeImmediate + Int64(delaySamples),
            AUAudioFrameCount(duration * sampleRate),
            parameter.address,
            value.clamped(to: range)
        )
    }

    private var parameterObserverToken: AUParameterObserverToken?

    /// Records automation for this parameter.
    /// - Parameter callback: Called on the main queue for each parameter event.
    public func recordAutomation(callback: @escaping (AUParameterAutomationEvent) -> Void) {
        parameterObserverToken = parameter.token(byAddingParameterAutomationObserver: { numberEvents, events in
            for index in 0 ..< numberEvents {
                let event = events[index]

                // Dispatching to main thread avoids the restrictions
                // required of parameter automation observers.
                Task { @MainActor in
                    callback(event)
                }
            }
        })
    }

    /// Stop calling the function passed to `recordAutomation`
    public func stopRecording() {
        if let token = parameterObserverToken {
            parameter.removeParameterObserver(token)
        }
    }

    /// Sends a .touch event to the parameter automation observer, beginning automation recording if
    /// enabled in ParameterAutomation.
    /// A value may be passed as the initial automation value. The current value is used if none is passed.
    /// - Parameter value: Initial value
    public func beginTouch(value: AUValue? = nil) {
        guard let value = value ?? parameter?.value else { return }
        parameter?.setValue(value, originator: nil, atHostTime: 0, eventType: .touch)
    }

    /// Sends a .release event to the parameter observation observer, ending any automation recording.
    /// A value may be passed as the final automation value. The current value is used if none is passed.
    /// - Parameter value: Final value
    public func endTouch(value: AUValue? = nil) {
        guard let value = value ?? parameter?.value else { return }
        parameter?.setValue(value, originator: nil, atHostTime: 0, eventType: .release)
    }
}
