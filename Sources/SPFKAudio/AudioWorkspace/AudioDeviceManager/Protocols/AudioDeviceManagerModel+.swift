import AVFoundation
import Foundation
import SimplyCoreAudio
import SPFKUtils

extension AudioDeviceManagerModel {
    public var matchesSystemSettings: Bool {
        deviceSettings.inputUID == defaultInputDevice?.uid &&
            deviceSettings.outputUID == defaultOutputDevice?.uid
    }

    public var sampleRateHasChanged: Bool {
        outputDeviceSampleRate != systemSampleRate
    }

    public var systemSampleRate: Double {
        get { systemFormat.sampleRate }

        set {
            guard AudioDefaults.isSupported(sampleRate: newValue) else {
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

    public var selectedDeviceSetttings: AudioDeviceSettings {
        AudioDeviceSettings(
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
}

// MARK: - Utilities

extension AudioDeviceManagerModel {
    /// CADefaultDeviceAggregate-49419-1
    internal func isEngineDefaultAggregate(device: AudioDevice) -> Bool {
        device.name.hasPrefix("CADefaultDevice")
    }

    public func lookupDevice(uid: String) -> AudioDevice? {
        AudioDevice.lookup(by: uid)
    }

    public func requestAudioInputAccess() async -> Bool? {
        guard hasInputDevice && deviceSettings.allowInput else {
            Log.error("🎤 Audio Disabled or no Input device.")
            return nil
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
