import AVFoundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManagerModel {
    public func isSupported(device: AudioDevice) -> Bool {
        guard let sampleRates = device.nominalSampleRates?.sorted(),
              let highestRate = sampleRates.last else { return false }
        return AudioDefaults.isSupported(sampleRate: highestRate)
    }

    public func isSupported(uid: String) async -> Bool {
        guard uid != AudioDeviceSettings.inputDeviceDisabledUID else { return true }

        guard let device = await AudioDevice.lookup(by: uid) else { return false }

        return isSupported(device: device)
    }

    public func setNominalSampleRate(to sampleRate: Double) async throws {
        try await setOutputSampleRate(to: sampleRate)

        do {
            try await setInputSampleRate(to: sampleRate)

        } catch {
            Log.error(error)
        }
    }

    public func setOutputSampleRate(to newValue: Double) async throws {
        guard let selectedOutputDevice = await selectedOutputDevice else { return }
        try await setSampleRate(device: selectedOutputDevice, to: newValue)
    }

    public func setInputSampleRate(to newValue: Double) async throws {
        guard let selectedInputDevice = await selectedInputDevice else { return }
        try await setSampleRate(device: selectedInputDevice, to: newValue)
    }
}

extension AudioDeviceManagerModel {
    internal func setSampleRate(device: AudioDevice, to newValue: Double) async throws {
        guard AudioDefaults.isSupported(sampleRate: newValue) else {
            throw NSError(description: "This sample rate \(newValue) isn't supported.")
        }

        guard let currentValue = device.nominalSampleRate,
              let supportedRates = device.nominalSampleRates else {
            throw NSError(description: "Failed to get current rate for \(device.name)")
        }

        guard currentValue != newValue else {
            Log.debug("\(device.name) is already set to \(newValue)")
            return
        }

        guard supportedRates.contains(newValue) else {
            let supportedRatesString = supportedRates.map({ $0.string }).joined(separator: ", ")

            throw NSError(description: "\(device.name) doesn't support \(newValue) Hz. Available rate\(supportedRates.pluralString) \(supportedRatesString)")
        }

        try await device.update(sampleRate: newValue)

        Log.debug("✓ Updated \(device.name) sample rate to", newValue)
    }
}
