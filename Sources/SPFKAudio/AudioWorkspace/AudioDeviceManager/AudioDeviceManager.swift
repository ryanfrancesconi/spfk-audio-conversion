// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKAudioHardware
import SPFKUtils
import SPFKUtilsC

/// In general, no longer keeping different device preferences from the system audio due
/// to incompatibilities with AVAudioEngine and its inputNode inflexibility.
/// The exception is: if input is disabled, still use
/// the engine audioUnit output directly to the output device selection.
/// NOTE: this method of direct setting of the device with no input doesn't work with airpods and
/// potentially other bluetooth I/O headsets as well.
public class AudioDeviceManager: AudioDeviceManagerModel {
    public enum Event {
        case sampleRateChanged(Double)
        case inputDeviceChanged(device: AudioDevice)
        case outputDeviceChanged(device: AudioDevice)
        case deviceListChanged(addedDevices: [AudioDevice], removedDevices: [AudioDevice])
        case deviceProcessorOverload
        case error(Error)

        case configurationChanged(Set<ConfigurationOption>)
    }

    public enum ConfigurationOption: Hashable {
        case sampleRateChanged
        case outputDeviceChanged
        case inputDeviceChanged
    }

    public weak var delegate: AudioDeviceManagerDelegate?

    func send(event: Event) {
        Task { @MainActor in
            delegate?.audioDeviceManager(event: event)
        }
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

    public var selectedInputDevice: AudioDevice? {
        guard deviceSettings.allowInput else { return nil }

        return hardware.defaultInputDevice
    }

    public var selectedOutputDevice: AudioDevice? {
        allowInput ? defaultOutputDevice : selectedEngineOutputDevice
    }

    public var defaultInputDevice: AudioDevice? { hardware.defaultInputDevice }
    public var defaultOutputDevice: AudioDevice? { hardware.defaultOutputDevice }
    public var engineOutputNode: AVAudioOutputNode? { delegate?.audioEngineOutputNode }

    public var deviceSettings = AudioDeviceSettings()

    public init(settings: AudioDeviceSettings = .init()) {
        // default to the system selected devices if nothing is passed in
        deviceSettings = AudioDeviceSettings(
            inputUID: settings.inputUID ?? defaultInputDevice?.uid,
            outputUID: settings.outputUID ?? defaultOutputDevice?.uid
        )

        Log.debug(deviceSettings)

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
            try setEngineNodeOutput(to: device)
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
        if !allowInput {
            try reconnectNodeOutput()
        }

        try updatePreferredOutputChannels()
    }
}
