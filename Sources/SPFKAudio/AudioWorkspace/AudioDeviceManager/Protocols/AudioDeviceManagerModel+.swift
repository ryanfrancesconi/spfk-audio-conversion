import AVFoundation
import Foundation
import SPFKAudioHardware
import SPFKUtils

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
            await allDevices.first { isEngineDefaultAggregate(device: $0) }
        }
    }

    public var allowInput: Bool {
        get async {
            let hasInputDevice = await hasInputDevice

            return deviceSettings.allowInput && hasInputDevice
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
            guard let inputLatency = await inputLatency,
                  let inputDeviceSampleRate = await inputDeviceSampleRate else { return nil }
            let seconds = TimeInterval(inputLatency) / inputDeviceSampleRate
            return seconds
        }
    }
}

// MARK: - Utilities

extension AudioDeviceManagerModel {
    /// CADefaultDeviceAggregate-49419-1
    internal func isEngineDefaultAggregate(device: AudioDevice) -> Bool {
        device.name.hasPrefix("CADefaultDevice")
    }

    public func requestAudioInputAccess() async -> Bool? {
        guard await hasInputDevice && deviceSettings.allowInput else {
            Log.error("🎤 Audio Disabled or no Input device.")
            return nil
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
