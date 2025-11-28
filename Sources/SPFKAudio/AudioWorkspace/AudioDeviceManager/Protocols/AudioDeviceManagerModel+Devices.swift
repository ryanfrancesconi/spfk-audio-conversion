import AsyncAlgorithms
import AVFoundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManagerModel {
    public var nonAggregateDevices: [AudioDevice] {
        get async {
            await hardware.nonAggregateDevices
        }
    }

    public var nonAggregateOutputDevices: [AudioDevice] { // unused spfk
        get async {
            let devices = await nonAggregateDevices

            return await devices.async.filter {
                await $0.physicalChannels(scope: .output) > 0
            }.toArray()
        }
    }

    public var aggregateDevices: [AudioDevice] {
        get async {
            await hardware.aggregateDevices
        }
    }

    public var inputDevices: [AudioDevice] {
        get async {
            await hardware.inputDevices
        }
    }

    public var compatibleInputDevices: [AudioDevice] { // unused spfk
        get async {
            await inputDevices.async.filter {
                guard let nominalSampleRates = $0.nominalSampleRates else {
                    return false
                }

                return await nominalSampleRates.async.contains { sampleRate in
                    await AudioDefaults.shared.isSupported(
                        sampleRate: sampleRate
                    )
                }
            }.toArray()
        }
    }

    public var outputDevices: [AudioDevice] {
        get async {
            await hardware.outputDevices
        }
    }

    public var bluetoothDevices: [AudioDevice] {
        get async {
            await hardware.bluetoothDevices
        }
    }

    public var splitDevices: [SplitAudioDevice] {
        get async {
            await hardware.splitDevices
        }
    }
}

extension AudioDeviceManagerModel {
    /// This is a lookup based on the preference UID
    /// Device can be different than the system if inputNode
    /// is disabled. Otherwise return nil.
    public var deviceSettingsOutputDevice: AudioDevice? {
        get async {
            guard await !allowInput,
                  let uid = deviceSettings.outputUID,
                  let device = await AudioDevice.lookup(uid: uid)
            else {
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
}

extension SplitAudioDevice {
    public var description: String {
        get async {
            var out = ""

            out += "input: \(input.description)"

            if await !inputIsSupported {
                out += " (Unsupported Device) "
            }

            out += " output: \(output.description)"

            if await !outputIsSupported {
                out += " (Unsupported Device) "
            }

            return out
        }
    }

    /// Some bluetooth headphones like AirPods do not support clear disabling of input,
    /// so in this case the only way to use them is by selecting a different input device
    /// such as the internal mic. This is unintuitive.
    public var supportsDisabledInput: Bool {
        get async {
            await inputIsSupported
        }
    }

    public var inputIsSupported: Bool {
        get async {
            guard let rates = input.getNominalSampleRates(scope: .input) else {
                return false
            }

            return await check(rates: rates)
        }
    }

    public var outputIsSupported: Bool {
        get async {
            guard let rates = output.getNominalSampleRates(scope: .output)
            else {
                return false
            }

            return await check(rates: rates)
        }
    }

    private func check(rates: [Double]) async -> Bool {
        return await rates.async.contains { sampleRate in
            await AudioDefaults.shared.isSupported(sampleRate: sampleRate)
        }
    }
}
