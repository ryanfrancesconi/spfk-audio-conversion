import AVFoundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManagerModel {
    public var allNonAggregateDevices: [AudioDevice] {
        allDevices.filter { !$0.isAggregateDevice }
    }

    public var allNonAggregateOutputDevices: [AudioDevice] {
        allNonAggregateDevices.filter { $0.channels(scope: .output) > 0 }
    }

    public var aggregateDevices: [AudioDevice] {
        allDevices.filter {
            $0.transportType == .aggregate
        }
    }

    public var allInputDevices: [AudioDevice] {
        allNonAggregateDevices.filter {
            $0.channels(scope: .input) > 0
        }
    }

    public var allCompatibleInputDevices: [AudioDevice] {
        allInputDevices.filter {
            $0.nominalSampleRates?.contains { AudioDefaults.isSupported(sampleRate: $0) } == true
        }
    }

    public var allOutputDevices: [AudioDevice] {
        allDevices.filter {
            $0.channels(scope: .output) > 0
        }
    }

    public var bluetoothDevices: [AudioDevice] {
        allDevices.filter {
            $0.transportType == .bluetooth
        }
    }
}

extension AudioDeviceManagerModel {
    /// This is a lookup based on the preference UID
    /// Device can be different than the system if inputNode
    /// is disabled. Otherwise return nil.
    public var selectedEngineOutputDevice: AudioDevice? {
        guard !allowInput,
              let uid = deviceSettings.outputUID,
              let device = AudioDevice.lookup(by: uid) else {
            return nil
        }

        return device
    }

    public var selectedOutputDeviceName: String {
        selectedOutputDevice?.name ?? "(Unnamed Output Device)"
    }

    /// Search for input and output devices that have matching `modelUID` values such
    /// as for bluetooth headphones that have an integrated mic.
    public var deviceIOPairs: [LinkedAudioDevice] {
        var out = [LinkedAudioDevice]()

        let allDevices = allDevices

        let uids = allDevices.compactMap { $0.modelUID }.removingDuplicates()

        for uid in uids {
            let devices = allDevices.filter { $0.modelUID == uid }

            let input = devices.first { $0.isInputOnlyDevice }
            let output = devices.first { $0.isOutputOnlyDevice }

            if let input, let output {
                out.append(
                    LinkedAudioDevice(input: input, output: output)
                )
            }
        }
        return out
    }

    public func preferredChannelsDescription(device: AudioDevice, scope: Scope) -> String? {
        guard let preferredChannelsForStereo = device.preferredChannelsForStereo(scope: scope) else { return nil }

        var namedChannels = device.namedChannels(scope: scope).filter {
            $0.channel == preferredChannelsForStereo.left ||
                $0.channel == preferredChannelsForStereo.right
        }

        namedChannels = namedChannels.sorted(by: { lhs, rhs -> Bool in
            lhs.channel < rhs.channel
        })

        let stringValues = namedChannels.map {
            $0.description
        }

        return stringValues.joined(separator: " + ")
    }
}
