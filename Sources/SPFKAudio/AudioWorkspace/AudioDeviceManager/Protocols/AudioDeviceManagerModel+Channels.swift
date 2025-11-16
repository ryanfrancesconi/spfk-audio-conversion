import AVFoundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManagerModel {
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
}
