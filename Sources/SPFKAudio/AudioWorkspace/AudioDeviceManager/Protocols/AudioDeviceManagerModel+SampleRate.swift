import AVFoundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManagerModel {
    public func isSupported(device: AudioDevice) async -> Bool {
        guard let sampleRates = device.nominalSampleRates?.sorted(),
              let highestRate = sampleRates.last else { return false }
        return await AudioDefaults.shared.isSupported(sampleRate: highestRate)
    }

    public func isSupported(uid: String) async -> Bool {
        guard uid != AudioDeviceSettings.inputDeviceDisabledUID else { return true }

        do {
            let device = try await AudioDevice.lookup(uid: uid)
            return await isSupported(device: device)
        } catch {
            Log.error(error)
            return false
        }
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
    func setSampleRate(device: AudioDevice, to newValue: Double) async throws {
        guard await AudioDefaults.shared.isSupported(sampleRate: newValue) else {
            throw NSError(description: "This sample rate \(newValue) isn't supported.")
        }

        guard let currentValue = device.nominalSampleRate,
              let supportedRates = device.nominalSampleRates
        else {
            throw NSError(description: "Failed to get current rate for \(device.name)")
        }

        guard currentValue != newValue else {
            Log.debug("\(device.name) is already set to \(newValue)")
            return
        }

        guard supportedRates.contains(newValue) else {
            let supportedRatesString = supportedRates.map(\.string).joined(separator: ", ")

            throw NSError(description: "\(device.name) doesn't support \(newValue) Hz. Available rate\(supportedRates.pluralString) \(supportedRatesString)")
        }

        try await device.sampleRateUpdater.updateAndWait(sampleRate: newValue)

        Log.debug("✓ Updated \(device.name) sample rate to", newValue)
    }
}
