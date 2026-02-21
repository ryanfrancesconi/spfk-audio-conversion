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

    public var selectedInputDevice: AudioDevice? {
        get async {
            await hardware.defaultInputDevice
        }
    }

    public var selectedOutputDevice: AudioDevice? {
        get async {
            let allowInput = await allowInput
            let defaultDevice = await hardware.defaultOutputDevice
            let preferenceDevice = try? await deviceSettingsOutputDevice()

            guard !allowInput else {
                return defaultDevice
            }

            return preferenceDevice ?? defaultDevice
        }
    }

    public var engineOutputNode: AVAudioOutputNode? {
        delegate?.audioEngineOutputNode
    }
}
