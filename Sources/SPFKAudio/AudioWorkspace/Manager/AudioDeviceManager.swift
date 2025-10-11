// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SimplyCoreAudio
import SPFKUtils
import SPFKUtilsC

// In general, no longer keeping different device preferences from the system audio due
// to incompatibilities with AVAudioEngine and its inputNode inflexibility.
// The exception is: if input is disabled, still use
// the engine audioUnit output directly to the output device selection.
// NOTE: this method of direct setting of the device with no input doesn't work with airpods and
// potentially other bluetooth I/O headsets as well.

public class AudioDeviceManager: AudioDeviceManagerModel {
    public enum Event {
        case sampleRateChanged(Double)
        case inputDeviceChanged(device: AudioDevice)
        case outputDeviceChanged(device: AudioDevice)
        case deviceListChanged(addedDevices: [AudioDevice], removedDevices: [AudioDevice])
        case deviceProcessorOverload
    }

    public weak var delegate: AudioDeviceManagerDelegate?

    func send(event: Event) {
        delegate?.audioDeviceManager(event: event)
    }

    var hardwareObservers: [NSObjectProtocol] = []
    var inputDeviceObserver: NSObjectProtocol?
    var outputDeviceObserver: NSObjectProtocol?

    public let hardware = SimplyCoreAudio()

    // MARK: - Latency

    // Cache this value for the selected device
    internal var _inputLatency: UInt32?
    public var inputLatency: UInt32? {
        if let _inputLatency { return _inputLatency }
        _inputLatency = inputDeviceLatency
        return _inputLatency
    }

    private var _bufferSize: UInt32 = 256
    public var bufferSize: UInt32 {
        get { _bufferSize }

        set {
            guard newValue != _bufferSize else { return }

            // the engine doesn't like this if input is disabled...
            guard deviceSettings.allowInput && allowInput else {
                Log.error("AVAudioEngine doesn't like the hardware buffer size changed when there is no input.")
                return
            }

            _bufferSize = newValue
            updateBufferSize()
        }
    }

    // TODO: once this model protocol is adopted, won't need this static struct and can keep a class variable here
    public var systemFormat: AVAudioFormat {
        get { AudioDefaults.systemFormat }

        set {
            AudioDefaults.systemFormat = newValue

            do {
                try setNominalSampleRate(to: newValue.sampleRate)
            } catch {
                Log.error(error)
            }
        }
    }

    // MARK: - Device convenience

    public var allDevices: [AudioDevice] { hardware.allDevices }

    public var bluetoothDevices: [AudioDevice] {
        allDevices.filter {
            $0.transportType == .bluetooth
        }
    }

    public var aggregateDevices: [AudioDevice] {
        allDevices.filter {
            $0.transportType == .aggregate
        }
    }

    public var selectedInputDevice: AudioDevice? {
        guard deviceSettings.allowInput else { return nil }
        return hardware.defaultInputDevice
    }

    public var selectedOutputDevice: AudioDevice? {
        allowInput ? hardware.defaultOutputDevice :
            selectedEngineOutputDevice
    }

    public var defaultInputDevice: AudioDevice? { hardware.defaultInputDevice }
    public var defaultOutputDevice: AudioDevice? { hardware.defaultOutputDevice }

    public var deviceSettings = AudioDeviceSettings()

    /// return the current engine in this block so that the `AudioDeviceManager` can set a device on it's output audio unit
    internal var engineRef: AVAudioEngine? {
        delegate?.audioEngineAccess?.engine
    }

    public var engineOutputNode: AVAudioOutputNode? { engineRef?.outputNode }

    public init(settings: AudioDeviceSettings = AudioDeviceSettings()) {
        // default to the system selected devices if nothing is passed in
        deviceSettings = AudioDeviceSettings(
            inputUID: settings.inputUID ?? defaultInputDevice?.uid,
            outputUID: settings.outputUID ?? defaultOutputDevice?.uid
        )

        addHardwareObservers()
    }

    deinit {
        removeHardwareObservers()
    }

    private func updateBufferSize() {
        if hasInputDevice, let device = selectedInputDevice {
            if !device.setBufferFrameSize(bufferSize, scope: .input) {
                Log.error("Unable to set input buffer frame size for", device.name)
            }
            if !device.setBufferFrameSize(bufferSize, scope: .output) {
                Log.error("Unable to set output buffer frame size for", device.name)
            }

            Log.debug("🎤 Input Latency", device.latency(scope: .input), inputLatencyInSeconds)
        }

        if let device = selectedOutputDevice {
            if !device.setBufferFrameSize(bufferSize, scope: .input) {
                Log.error("Unable to set input buffer frame size for", device.name)
            }
            if !device.setBufferFrameSize(bufferSize, scope: .output) {
                Log.error("Unable to set output buffer frame size for", device.name)
            }

            Log.debug("🎤 Output Latency", device.latency(scope: .output))
        }

        Log.debug("🔈 Updated I/O Buffer Size to", bufferSize)
    }

    // MARK: - Device Setters

    public func setInput(device: AudioDevice) {
        guard device != selectedInputDevice else { return }

        defer {
            try? setInputSampleRate(to: systemSampleRate)
        }

        deviceSettings.inputUID = device.uid

        // will set device
        device.isDefaultInputDevice = true
        addInputDeviceObserver(for: device)

        _inputLatency = nil // uncache this
    }

    public func setOutput(device: AudioDevice) throws {
        guard device != selectedOutputDevice else { return }

        defer {
            try? setOutputSampleRate(to: systemSampleRate)
        }

        deviceSettings.outputUID = device.uid

        guard deviceSettings.allowInput else {
            try setNodeOutput(to: device)
            // will call updatePreferredOutputChannels
            return
        }

        // will set device
        device.isDefaultOutputDevice = true

        try updatePreferredOutputChannels()
        addOutputDeviceObserver(for: device)
    }
}

extension AudioDeviceManager {
    public func reconnect() throws {
        if allowInput {
            ExceptionCatcherOperation({ [weak self] in
                guard let self else { return }

                // create input node
                _ = delegate?.audioEngineAccess?.inputNode

                verifyInputSampleRate()

            }, { exception in
                Log.error(exception.debugDescription)
            })

        } else {
            try reconnectNodeOutput()
        }

        try updatePreferredOutputChannels()
    }

    /// Make sure the current input device is set to a valid rate,
    /// otherwise choose a different device
    func verifyInputSampleRate() {
        let inputFormat = delegate?.audioEngineAccess?.inputFormat

        guard let inputSampleRate = inputFormat?.sampleRate,
              inputSampleRate < AudioDefaults.minimumSampleRateSupported else {
            return
        }

        guard let firstCompatibleInputDevice else { return }

        setInput(device: firstCompatibleInputDevice)

        do {
            try setNominalSampleRate(to: systemSampleRate)

        } catch {
            Log.error(error)
        }
    }
}

public protocol AudioDeviceManagerDelegate: AnyObject, AudioEngineAccess {
    func audioDeviceManager(event: AudioDeviceManager.Event)
}
