// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase
import SPFKBaseC

/// In general, no longer keeping different device preferences from the system audio due
/// to incompatibilities with AVAudioEngine and its inputNode inflexibility.
/// The exception is: if input is disabled, still use
/// the engine audioUnit output directly to the output device selection.
/// NOTE: this method of direct setting of the device with no input doesn't work with airpods and
/// potentially other bluetooth I/O headsets as well.
public final class AudioDeviceManager: AudioDeviceManagerModel {
    public enum Event: Sendable {
        case sampleRateChanged(device: AudioDevice)
        case inputDeviceChanged(device: AudioDevice)
        case outputDeviceChanged(device: AudioDevice)
        case deviceListChanged(event: DeviceStatusEvent)
        case deviceProcessorOverload
        case error(Error)
        case configurationChanged(Set<ConfigurationOption>)
    }

    public enum ConfigurationOption: Hashable, Sendable {
        case sampleRateChanged
        case outputDeviceChanged
        case inputDeviceChanged
    }

    public weak var delegate: AudioDeviceManagerDelegate?

    var hardwareObservers: [NSObjectProtocol] = []

    public let hardware: AudioHardwareManager = .shared

    // MARK: - Latency

    // Cache this value for the selected device
    var _inputLatency: UInt32?
    public var inputLatency: UInt32? {
        get async {
            if let _inputLatency { return _inputLatency }
            _inputLatency = await inputDeviceLatency
            return _inputLatency
        }
    }

    private var _bufferSize: UInt32 = 256
    public var bufferSize: UInt32 {
        _bufferSize
    }

    public var systemFormat: AVAudioFormat {
        get async {
            await AudioDefaults.shared.systemFormat
        }
    }

    // MARK: - Device convenience

    public var allDevices: [AudioDevice] {
        get async {
            await hardware.allDevices
        }
    }

    public var selectedInputDevice: AudioDevice? {
        get async {
            guard deviceSettings.allowInput else { return nil }

            return await hardware.defaultInputDevice
        }
    }

    public var selectedOutputDevice: AudioDevice? {
        get async {
            await allowInput ?
                await hardware.defaultOutputDevice :
                deviceSettingsOutputDevice
        }
    }

    public var defaultInputDevice: AudioDevice? {
        get async {
            await hardware.defaultInputDevice
        }
    }

    public var defaultOutputDevice: AudioDevice? {
        get async {
            await hardware.defaultOutputDevice
        }
    }

    public var engineOutputNode: AVAudioOutputNode? { delegate?.audioEngineOutputNode }

    public var deviceSettings = AudioDeviceSettings()

    public init() {}

    public func setup(settings: AudioDeviceSettings = .init()) async throws {
        Log.debug(settings)

        let defaultInputUID = await hardware.defaultInputDevice?.uid
        let defaultOutputUID = await hardware.defaultOutputDevice?.uid

        // default to the system selected devices if nothing is passed in
        deviceSettings = AudioDeviceSettings(
            inputUID: settings.inputUID ?? defaultInputUID,
            outputUID: settings.outputUID ?? defaultOutputUID
        )

        try await registerNotifications()

        guard let deviceSampleRate = await selectedOutputDevice?.nominalSampleRate else {
            throw NSError(description: "Failed to get device sample rate")
        }

        try await update(systemSampleRate: deviceSampleRate)
    }

    private func registerNotifications() async throws {
        try await hardware.start()
        addHardwareObservers()
    }

    public func unregisterNotifications() async throws {
        removeHardwareObservers()
        try await hardware.unregister()
    }
}

extension AudioDeviceManager {
    public func updateBufferSize(newValue: UInt32) async {
        guard newValue != _bufferSize else { return }

        let allowInput = await allowInput

        // the engine doesn't like this if input is disabled...
        guard deviceSettings.allowInput, allowInput else {
            Log.error("AVAudioEngine doesn't like the hardware buffer size changed when there is no input.")
            return
        }

        _bufferSize = newValue

        if await hasInputDevice,
           let device = await selectedInputDevice
        {
            if kAudioHardwareNoError != device.setBufferFrameSize(bufferSize, scope: .input) {
                Log.error("Unable to set input buffer frame size for", device.name)
            }

            if kAudioHardwareNoError != device.setBufferFrameSize(bufferSize, scope: .output) {
                Log.error("Unable to set output buffer frame size for", device.name)
            }

            await Log.debug("🎤 Input Latency", device.latency(scope: .input), inputLatencyInSeconds)
        }

        if let device = await selectedOutputDevice {
            if kAudioHardwareNoError != device.setBufferFrameSize(bufferSize, scope: .input) {
                Log.error("Unable to set input buffer frame size for", device.name)
            }

            if kAudioHardwareNoError != device.setBufferFrameSize(bufferSize, scope: .output) {
                Log.error("Unable to set output buffer frame size for", device.name)
            }

            await Log.debug("🎤 Output Latency", device.latency(scope: .output))
        }

        Log.debug("🔈 Updated I/O Buffer Size to", bufferSize)
    }

    // MARK: - Device Setters

    public func setInput(device: AudioDevice) async throws {
        deviceSettings.inputUID = device.uid

        // will set device
        try device.promote(to: .defaultInput)

        _inputLatency = nil // uncache this

        try await setInputSampleRate(to: systemSampleRate)
    }

    public func setOutput(device: AudioDevice) async throws {
        deviceSettings.outputUID = device.uid

        guard deviceSettings.allowInput else {
            try await setEngineNodeOutput(to: device)
            // will call updatePreferredOutputChannels
            return
        }

        // will set device
        try device.promote(to: .defaultOutput)
        try await updatePreferredOutputChannels()
        try await setOutputSampleRate(to: systemSampleRate)
    }

    public func reconnect() async throws {
        let allowInput = await self.allowInput

        if !allowInput {
            try await reconnectNodeOutput()
        }

        try await updatePreferredOutputChannels()
    }
}
