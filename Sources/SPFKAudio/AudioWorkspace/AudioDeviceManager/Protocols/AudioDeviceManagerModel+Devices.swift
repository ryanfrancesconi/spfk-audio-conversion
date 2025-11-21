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
                  let device = await AudioDevice.lookup(uid: uid) else {
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

extension SplitAudioDevice {
    public var description: String {
        var out = ""

        out += "input: \(input.description)"

        if !inputIsSupported {
            out += " (Unsupported Device) "
        }

        out += " output: \(output.description)"

        if !outputIsSupported {
            out += " (Unsupported Device) "
        }

        return out
    }

    /// Some bluetooth headphones like AirPods do not support clear disabling of input,
    /// so in this case the only way to use them is by selecting a different input device
    /// such as the internal mic. This is unintuitive.
    public var supportsDisabledInput: Bool {
        inputIsSupported
    }

    public var inputIsSupported: Bool {
        guard let rates = input.getNominalSampleRates(scope: .input) else {
            return false
        }

        return check(rates: rates)
    }

    public var outputIsSupported: Bool {
        guard let rates = output.getNominalSampleRates(scope: .output) else {
            return false
        }

        return check(rates: rates)
    }

    private func check(rates: [Double]) -> Bool {
        rates.contains { AudioDefaults.isSupported(sampleRate: $0) }
    }
}
