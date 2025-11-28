import AVFoundation
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManagerModel {
    /// - Returns: A collection of named channels for the selected input device
    public var selectedInputDeviceChannels: [AudioDeviceNamedChannel] {
        get async {
            await selectedInputDevice?.namedChannels(scope: .input) ?? []
        }
    }

    /// - Returns: A collection of named channels for the selected output device
    public var selectedOutputDeviceChannels: [AudioDeviceNamedChannel] {
        get async {
            await selectedOutputDevice?.namedChannels(scope: .output) ?? []
        }
    }

    public var numberOfInputChannels: Int {
        get async {
            guard let layoutChannels = await selectedInputDevice?.physicalChannels(scope: .input) else {
                return 0
            }

            return Int(layoutChannels)
        }
    }

    public var numberOfOutputChannels: Int {
        get async {
            guard let layoutChannels = await selectedOutputDevice?.physicalChannels(scope: .output) else {
                return 0
            }

            return Int(layoutChannels)
        }
    }
}
