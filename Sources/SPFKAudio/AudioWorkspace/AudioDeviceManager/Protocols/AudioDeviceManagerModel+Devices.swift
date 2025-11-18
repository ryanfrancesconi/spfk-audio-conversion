import AsyncAlgorithms
import AVFoundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManagerModel {
    public var allNonAggregateDevices: [AudioDevice] {
        get async {
            await allDevices.async.filter { await !$0.isAggregateDevice }.toArray()
        }
    }

    public var allNonAggregateOutputDevices: [AudioDevice] {
        get async {
            await allNonAggregateDevices.async.filter { await $0.channels(scope: .output) > 0 }.toArray()
        }
    }

    public var aggregateDevices: [AudioDevice] {
        get async {
            await allDevices.filter {
                $0.transportType == .aggregate
            }
        }
    }

    public var allInputDevices: [AudioDevice] {
        get async {
            await allNonAggregateDevices.async.filter {
                await $0.channels(scope: .input) > 0
            }.toArray()
        }
    }

    public var allCompatibleInputDevices: [AudioDevice] {
        get async {
            await allInputDevices.filter {
                $0.nominalSampleRates?.contains { AudioDefaults.isSupported(sampleRate: $0) } == true
            }
        }
    }

    public var allOutputDevices: [AudioDevice] {
        get async {
            await allDevices.async.filter {
                await $0.channels(scope: .output) > 0
            }.toArray()
        }
    }

    public var bluetoothDevices: [AudioDevice] {
        get async {
            await allDevices.filter {
                $0.transportType == .bluetooth
            }
        }
    }
}

extension AudioDeviceManagerModel {
    /// This is a lookup based on the preference UID
    /// Device can be different than the system if inputNode
    /// is disabled. Otherwise return nil.
    public var selectedEngineOutputDevice: AudioDevice? {
        get async {
            guard await !allowInput,
                  let uid = deviceSettings.outputUID,
                  let device = await AudioDevice.lookup(by: uid) else {
                return nil
            }

            return device
        }
    }

    public var selectedOutputDeviceName: String {
        get async {
            await selectedOutputDevice?.name ?? "(Unnamed Output Device)"
        }
    }

    /// Search for input and output devices that have matching `modelUID` values such
    /// as for bluetooth headphones that have an integrated mic.
    public var deviceIOPairs: [LinkedAudioDevice] {
        get async {
            var out = [LinkedAudioDevice]()

            let allDevices = await allDevices

            let uids = allDevices.compactMap { $0.modelUID }.removingDuplicates()

            for uid in uids {
                let devices = allDevices.filter { $0.modelUID == uid }

                let input = await devices.async.first { await $0.isInputOnlyDevice }
                let output = await devices.async.first { await $0.isOutputOnlyDevice }

                if let input, let output {
                    out.append(
                        LinkedAudioDevice(input: input, output: output)
                    )
                }
            }
            return out
        }
    }

    public func preferredChannelsDescription(device: AudioDevice, scope: Scope) async -> String? {
        guard let preferredChannelsForStereo = device.preferredChannelsForStereo(scope: scope) else { return nil }

        var namedChannels = await device.namedChannels(scope: scope).filter {
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
