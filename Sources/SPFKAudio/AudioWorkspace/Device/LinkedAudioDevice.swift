import Foundation
import SimplyCoreAudio

/// Input and output devices that have matching `modelUID` values such
/// as for bluetooth headphones that have an integrated mic.
public struct LinkedAudioDevice: CustomStringConvertible {
    public var uid: String? {
        output?.uid ?? input?.uid
    }

    public var input: AudioDevice?
    public var output: AudioDevice?

    public var description: String {
        var out = ""

        if let input {
            out += "input: \(input.description)"

            if !inputIsSupported {
                out += " (Unsupported Device) "
            }
        }

        if let output {
            out += " output: \(output.description)"

            if !outputIsSupported {
                out += " (Unsupported Device) "
            }
        }

        return out
    }

    public var inputIsSupported: Bool {
        guard let rates = input?.nominalSampleRates else {
            return false
        }

        return check(rates: rates)
    }

    public var outputIsSupported: Bool {
        guard let rates = output?.nominalSampleRates else {
            return false
        }

        return check(rates: rates)
    }

    /// Some bluetooth headphones like AirPods do not support clear disabling of input,
    /// so in this case the only way to use them is by selecting a different input device
    /// such as the internal mic. This is unintuitive.
    public var supportsDisabledInput: Bool {
        inputIsSupported
    }

    private func check(rates: [Double]) -> Bool {
        rates.contains { $0 >= AudioDefaults.minimumSampleRateSupported }
    }

    public init(input: AudioDevice? = nil, output: AudioDevice? = nil) {
        self.input = input
        self.output = output
    }

    public func contains(device: AudioDevice) -> Bool {
        input == device || output == device
    }

    public func contains(uid: String) -> Bool {
        input?.uid == uid ||
            output?.uid == uid
    }
}
