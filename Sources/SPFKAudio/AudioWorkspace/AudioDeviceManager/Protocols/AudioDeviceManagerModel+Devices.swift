import AsyncAlgorithms
import AVFoundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase

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
            await allInputDevices.async.filter {
                guard let nominalSampleRates = $0.nominalSampleRates else { return false }

                return await nominalSampleRates.async.contains { sampleRate in
                    await AudioDefaults.shared.isSupported(sampleRate: sampleRate)
                }
            }.toArray()
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
    public var selectedEngineOutputDevice: AudioDevice? {
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
            guard let rates = output.getNominalSampleRates(scope: .output) else {
                return false
            }

            return await check(rates: rates)
        }
    }

    private func check(rates: [Double]) async -> Bool {
        // rates.contains { AudioDefaults.shared.isSupported(sampleRate: $0) }

        return await rates.async.contains { sampleRate in
            await AudioDefaults.shared.isSupported(sampleRate: sampleRate)
        }
    }
}
