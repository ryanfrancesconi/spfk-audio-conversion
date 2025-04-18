import SPFKUtils
import AVFoundation
import Foundation
import SimplyCoreAudio

extension AudioDeviceManagerModel {
    public var systemSampleRate: Double {
        get { systemFormat.sampleRate }

        set {
            guard newValue >= AudioDefaults.minimumSampleRateSupported else {
                Log.error(newValue, "isn't a supported sample rate so ignoring this event")
                return
            }

            guard let audioFormat = AVAudioFormat(
                standardFormatWithSampleRate: newValue,
                channels: systemFormat.channelCount
            ) else {
                return
            }

            systemFormat = audioFormat
        }
    }

    public var inputDeviceSampleRate: Double? { selectedInputDevice?.nominalSampleRate }
    public var outputDeviceSampleRate: Double? { selectedOutputDevice?.nominalSampleRate }

    public var selectedDeviceSetttings: DeviceSettings {
        DeviceSettings(
            inputUID: selectedInputDevice?.uid,
            outputUID: selectedOutputDevice?.uid
        )
    }

    public var engineDevice: AudioDevice? {
        allDevices.first { isEngineDefaultAggregate(device: $0) }
    }

    public var allowInput: Bool {
        deviceSettings.allowInput && hasInputDevice
    }

    public var hasInputDevice: Bool {
        selectedInputDevice != nil
    }

    public var inputDeviceLatency: UInt32? { selectedInputDevice?.latency(scope: .input) }
    public var outputDeviceLatency: UInt32? { selectedOutputDevice?.latency(scope: .output) }

    public var inputLatencyInSeconds: TimeInterval? {
        guard let inputLatency, let inputDeviceSampleRate else { return nil }
        let seconds = TimeInterval(inputLatency) / inputDeviceSampleRate
        return seconds
    }

    public var outputLatencyInSeconds: TimeInterval? {
        guard let outputLatency, let outputDeviceSampleRate else { return nil }
        let seconds = TimeInterval(outputLatency) / outputDeviceSampleRate
        return seconds
    }
}

extension AudioDeviceManagerModel {
    /// This is a lookup based on the preference UID
    /// Device can be different than the system if inputNode
    /// is disabled. Otherwise return nil.
    public var selectedEngineOutputDevice: AudioDevice? {
        guard !deviceSettings.allowInput,
              let uid = deviceSettings.outputUID,
              let device = AudioDevice.lookup(by: uid) else {
            return nil
        }

        return device
    }

    public var selectedOutputDeviceName: String {
        selectedOutputDevice?.name ?? "(Unnamed Output Device)"
    }

    /// - Returns: A collection of named channels for the selected input device
    public var selectedInputDeviceChannels: [AudioDevice.NamedChannel] {
        selectedInputDevice?.namedChannels(scope: .input) ?? []
    }

    /// - Returns: A collection of named channels for the selected output device
    public var selectedOutputDeviceChannels: [AudioDevice.NamedChannel] {
        selectedOutputDevice?.namedChannels(scope: .output) ?? []
    }

    public var numberOfInputChannels: Int {
        guard let layoutChannels = selectedInputDevice?.channels(scope: .input) else {
            return 0
        }
        return Int(layoutChannels)
    }

    public var numberOfOutputChannels: Int {
        guard let layoutChannels = selectedOutputDevice?.channels(scope: .output) else {
            return 0
        }
        return Int(layoutChannels)
    }

    public var allNonAggregateDevices: [AudioDevice] {
        allDevices.filter { !$0.isAggregateDevice }
    }

    public var allInputDevices: [AudioDevice] {
        allNonAggregateDevices.filter {
            $0.channels(scope: .input) > 0
        }
    }

    public var allOutputDevices: [AudioDevice] {
        allDevices.filter {
            $0.channels(scope: .output) > 0
        }
    }

    public var allNonAggregateOutputDevices: [AudioDevice] {
        allNonAggregateDevices.filter { $0.channels(scope: .output) > 0 }
    }

    public var firstCompatibleInputDevice: AudioDevice? {
        let compatibleInputs = allInputDevices.filter {
            $0.nominalSampleRates?.contains(where: { $0 >= AudioDefaults.minimumSampleRateSupported }) == true
        }.sorted { lhs, _ in
            // favor built-in mic
            lhs.transportType == .builtIn
        }

        return compatibleInputs.first
    }

    /// Search for input and output devices that have matching `modelUID` values such
    /// as for bluetooth headphones that have an integrated mic.
    public var deviceIOPairs: [LinkedAudioDevice] {
        var out = [LinkedAudioDevice]()

        let allDevices = allDevices

        let uids = allDevices.compactMap { $0.modelUID }.removingDuplicates()

        for uid in uids {
            let devices = allDevices.filter { $0.modelUID == uid }

            let input = devices.first { $0.isInputOnlyDevice }
            let output = devices.first { $0.isOutputOnlyDevice }

            if let input, let output {
                out.append(
                    LinkedAudioDevice(input: input, output: output)
                )
            }
        }
        return out
    }
}

// MARK: - Utilities

extension AudioDeviceManagerModel {
    /// CADefaultDeviceAggregate-49419-1
    internal func isEngineDefaultAggregate(device: AudioDevice) -> Bool {
        device.name.hasPrefix("CADefaultDevice")
    }

    public func isSupported(device: AudioDevice) -> Bool {
        guard let sampleRates = device.nominalSampleRates?.sorted(),
              let highestRate = sampleRates.last else { return false }
        return highestRate >= AudioDefaults.minimumSampleRateSupported
    }

    public func isSupported(uid: String) -> Bool {
        guard uid != DeviceSettings.inputDeviceDisabledUID else { return true }
        guard let device = lookupDevice(uid: uid) else { return false }
        return isSupported(device: device)
    }

    public func lookupDevice(uid: String) -> AudioDevice? {
        AudioDevice.lookup(by: uid)
    }

    public func requestAudioAccess(completionHandler: @escaping (Bool?) -> Void) {
        guard hasInputDevice && deviceSettings.allowInput else {
            Log.error("🎤 Audio Disabled or no Input device.")
            completionHandler(nil)
            return
        }

        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)

            Task { @MainActor in
                completionHandler(allowed)
            }
        }
    }

    public func setNominalSampleRate(to sampleRate: Double) throws {
        try setOutputSampleRate(to: sampleRate)

        do {
            try setInputSampleRate(to: sampleRate)

        } catch {
            Log.error(error)
        }
    }

    public func setOutputSampleRate(to newValue: Double) throws {
        guard let selectedOutputDevice else { return }
        try setSampleRate(device: selectedOutputDevice, sampleRate: newValue)
    }

    public func setInputSampleRate(to newValue: Double) throws {
        guard let selectedInputDevice else { return }
        try setSampleRate(device: selectedInputDevice, sampleRate: newValue)
    }

    public func supportedSampleRates(for device: AudioDevice) -> [Double] {
        device.nominalSampleRates?.sorted() ?? []
    }

    internal func setSampleRate(device: AudioDevice, sampleRate: Double) throws {
        guard sampleRate >= AudioDefaults.minimumSampleRateSupported else {
            throw NSError(description: "This sample rate \(sampleRate) isn't supported. The minimum rate is \(AudioDefaults.minimumSampleRateSupported)")
        }

        guard let deviceSampleRate = device.nominalSampleRate else {
            throw NSError(description: "Failed to get current rate for \(device.name)")
        }

        guard deviceSampleRate != sampleRate else {
            Log.debug("🔈 \(device.name) is already set to \(sampleRate)")
            return
        }

        let supportedRates = supportedSampleRates(for: device)
        let supportedRatesString = supportedRates.map({ $0.string }).joined(separator: ", ")

        guard supportedRates.contains(sampleRate) else {
            throw NSError(description: "\(device.name) doesn't support \(sampleRate) Hz. Available rate\(supportedRates.pluralString) \(supportedRatesString)")
        }

        if !device.setNominalSampleRate(sampleRate) {
            throw NSError(description: "Unable to set \(device.name) to \(sampleRate)")
        }

        Log.debug("🔈 Updated \(device.name) sample rate to", sampleRate)
    }
}
