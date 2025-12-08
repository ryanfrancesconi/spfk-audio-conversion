// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase
import SPFKBaseC

extension AudioDeviceManager {
    public var bufferSize: UInt32 {
        256 // _bufferSize
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
            await hardware.defaultInputDevice
        }
    }

    public var selectedOutputDevice: AudioDevice? {
        get async {
            let defaultDevice = await defaultOutputDevice
            let preferenceDevice = await deviceSettingsOutputDevice

            guard await !allowInput else {
                return defaultDevice
            }

            return preferenceDevice ?? defaultDevice
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
}
