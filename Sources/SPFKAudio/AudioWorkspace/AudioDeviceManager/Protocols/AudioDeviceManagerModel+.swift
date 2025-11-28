import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManagerModel {
    public var matchesSystemSettings: Bool {
        get async {
            let defaultInputUID = await defaultInputDevice?.uid
            let defaultOutputUID = await defaultOutputDevice?.uid

            return deviceSettings.inputUID == defaultInputUID &&
                deviceSettings.outputUID == defaultOutputUID
        }
    }

    public var sampleRateHasChanged: Bool {
        get async {
            await outputDeviceSampleRate != systemSampleRate
        }
    }
}

extension AudioDeviceManagerModel {
    public var systemSampleRate: Double {
        get async {
            await systemFormat.sampleRate
        }
    }

    public func update(systemSampleRate: Double) async throws {
        guard await AudioDefaults.shared.isSupported(sampleRate: systemSampleRate) else {
            Log.error(systemSampleRate, "isn't a supported sample rate so ignoring this event")
            return
        }

        guard let audioFormat = await AVAudioFormat(
            standardFormatWithSampleRate: systemSampleRate,
            channels: systemFormat.channelCount
        ) else {
            throw NSError(description: "Failed to create format")
        }

        try await update(systemFormat: audioFormat)
    }

    public func update(systemFormat: AVAudioFormat) async throws {
        await AudioDefaults.shared.update(systemFormat: systemFormat)

        try await setNominalSampleRate(to: systemFormat.sampleRate)

        Log.debug("🔊 Updated system format to", systemFormat)
    }

    public var inputDeviceSampleRate: Double? {
        get async {
            await selectedInputDevice?.nominalSampleRate
        }
    }

    public var outputDeviceSampleRate: Double? {
        get async {
            await selectedOutputDevice?.nominalSampleRate
        }
    }
}

extension AudioDeviceManagerModel {
    public var selectedDeviceSetttings: AudioDeviceSettings {
        get async {
            await AudioDeviceSettings(
                inputUID: selectedInputDevice?.uid,
                outputUID: selectedOutputDevice?.uid
            )
        }
    }

    public var engineDevice: AudioDevice? {
        get async {
            await allDevices.first { Self.isEngineDefaultAggregate(device: $0) }
        }
    }

    public var allowInput: Bool {
        get async {
            let hasInputDevice = await hasInputDevice
            let settingsAllow = deviceSettings.allowInput

            return settingsAllow && hasInputDevice
        }
    }

    public var hasInputDevice: Bool {
        get async {
            await selectedInputDevice != nil
        }
    }

    public var inputDeviceLatency: UInt32? {
        get async {
            await selectedInputDevice?.latency(scope: .input)
        }
    }

    public var outputDeviceLatency: UInt32? {
        get async {
            await selectedOutputDevice?.latency(scope: .output)
        }
    }

    public var inputLatencyInSeconds: TimeInterval? {
        get async {
            guard let inputLatency = await inputDeviceLatency,
                  let inputDeviceSampleRate = await inputDeviceSampleRate else { return nil }
            let seconds = TimeInterval(inputLatency) / inputDeviceSampleRate
            return seconds
        }
    }
}

// MARK: - Utilities

extension AudioDeviceManagerModel {
    /// CADefaultDeviceAggregate-49419-1
    static func isEngineDefaultAggregate(device: AudioDevice) -> Bool {
        device.name.hasPrefix("CADefaultDevice") // this is unstable logic
    }

    public func requestAudioInputAccess() async throws -> Bool {
        guard await hasInputDevice && deviceSettings.allowInput else {
            throw NSError(description: "Audio Disabled or no Input device.")
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        var authorized = false

        switch status {
        case .notDetermined:
            Log.error("notDetermined")

        case .restricted:
            Log.error("restricted")

        case .denied:
            Log.error("denied")

        case .authorized:
            authorized = true
            Log.debug("✅ authorized")

        @unknown default:
            assertionFailure()
        }

        guard !authorized else { return true }

        let allowed = await AVCaptureDevice.requestAccess(for: .audio)

        return allowed
    }
}
