import AVFoundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManagerModel {
    /// - Returns: A collection of named channels for the selected input device
    public var selectedInputDeviceChannels: [AudioDevice.NamedChannel] {
        get async {
            await selectedInputDevice?.namedChannels(scope: .input) ?? []
        }
    }

    /// - Returns: A collection of named channels for the selected output device
    public var selectedOutputDeviceChannels: [AudioDevice.NamedChannel] {
        get async {
            await selectedOutputDevice?.namedChannels(scope: .output) ?? []
        }
    }

    public var numberOfInputChannels: Int {
        get async {
            guard let layoutChannels = await selectedInputDevice?.channels(scope: .input) else {
                return 0
            }

            return Int(layoutChannels)
        }
    }

    public var numberOfOutputChannels: Int {
        get async {
            guard let layoutChannels = await selectedOutputDevice?.channels(scope: .output) else {
                return 0
            }

            return Int(layoutChannels)
        }
    }
}
