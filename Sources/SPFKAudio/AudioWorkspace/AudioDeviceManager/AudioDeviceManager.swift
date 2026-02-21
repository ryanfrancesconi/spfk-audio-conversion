// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

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
public final class AudioDeviceManager: AudioDeviceManagerModel, @unchecked Sendable {
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

    let delegate: (any AudioDeviceManagerDelegate)?

    public let hardware: AudioHardwareManager = .shared

    public var hardwareObservers: [NSObjectProtocol] = .init()

    public let deviceSettings = AudioDeviceSettings()

    var notificationTask: Task<Void, Error>?

    public init(delegate: AudioDeviceManagerDelegate? = nil) {
        self.delegate = delegate
    }

    public func setup(settings: AudioDeviceSettings = .init()) async throws {
        let defaultInputUID = await hardware.defaultInputDevice?.uid
        let defaultOutputUID = await hardware.defaultOutputDevice?.uid

        await deviceSettings.update(inputUID: settings.inputUID ?? defaultInputUID)
        await deviceSettings.update(outputUID: settings.outputUID ?? defaultOutputUID)

        try await registerNotifications()

        guard let selectedOutputDevice = await selectedOutputDevice else {
            throw NSError(description: "Failed to get selectedOutputDevice")
        }

        guard let deviceSampleRate = selectedOutputDevice.nominalSampleRate else {
            throw NSError(description: "\(selectedOutputDevice.nameAndID): Failed to get sample rate")
        }

        await Log.debug("deviceSettings:", deviceSettings.description, deviceSampleRate)

        try await update(systemSampleRate: deviceSampleRate)

        try await reconnect()
    }

    @MainActor private func registerNotifications() async throws {
        try await hardware.start()
        addObservers()
    }

    @MainActor public func dispose() async throws {
        removeObservers()
        try await hardware.unregister()
    }
}

extension AudioDeviceManager {
    public func updateBufferSize(newValue: UInt32) async {
        let allowInput = await allowInput

        // the engine doesn't like this if input is disabled...
        guard await deviceSettings.allowInput, allowInput else {
            Log.error("AVAudioEngine doesn't like the hardware buffer size changed when there is no input.")
            return
        }

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
        await deviceSettings.update(inputUID: device.uid)

        // will set device
        try device.promote(to: .defaultInput)

        try await setInputSampleRate(to: systemSampleRate)
    }

    public func setOutput(device: AudioDevice) async throws {
        await deviceSettings.update(outputUID: device.uid)

        guard await deviceSettings.allowInput else {
            // No Input

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
        let allowInput = await allowInput

        guard !allowInput else { return }

        try await reconnectNodeOutput()
    }
}
