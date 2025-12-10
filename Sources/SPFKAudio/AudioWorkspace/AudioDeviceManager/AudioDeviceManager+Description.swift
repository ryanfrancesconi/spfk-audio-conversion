import Foundation
import SPFKAudioHardware

extension AudioDeviceManager {
    public func detailedDescription() async throws -> String {
        let inputDevices = try await hardware.inputDevices()
        let outputDevices = try await hardware.outputDevices()

        var string = ""

        await string += "↑ Selected Output Device: \(selectedOutputDevice?.name ?? "No Output") @ \(selectedOutputDevice?.actualSampleRate ?? 0) Hz, \(numberOfOutputChannels) Channel\n"

        if let selectedInputDevice = await selectedInputDevice {
            await string += "↓ Selected Input Device: \(selectedInputDevice.name) @ \(selectedInputDevice.actualSampleRate ?? 0) Hz, \(numberOfInputChannels) Channel\n\n"
        } else {
            string += "↓ Input Device: Disabled or no device detected on this system. ⚠️\n\n"
        }

        if let engineDevice = try await engineDevice() {
            await string += deviceDescription(engineDevice) + "\n"
        }

        string += "\n"

        let outputDeviceNames = outputDevices.map(\.name).sorted()
        string += "↑ Output Devices: " + outputDeviceNames.joined(separator: ", ")
        string += "\n"

        let inputDeviceNames = inputDevices.map(\.name).sorted()
        string += "↓ Input Devices: " + inputDeviceNames.joined(separator: ", ")
        string += "\n\n"

        return string
    }

    public func deviceDescription(_ device: AudioDevice) async -> String {
        let isSelectedOutputDevice = await device == selectedOutputDevice
        let isSelectedInputDevice = await device == selectedInputDevice

        let selectedInputIcon = isSelectedInputDevice ? "🤚 isSelectedInputDevice " : ""
        let selectedOutputIcon = isSelectedOutputDevice ? "🤚 isSelectedOutputDevice " : ""

        let content = "\(selectedInputIcon)\(selectedOutputIcon)\n"

        return await content + device.detailedDescription
    }
}

extension AudioDevice {
    public var detailedDescription: String {
        get async {
            let aggregateIcon = await isAggregateDevice ? " (Aggregate) " : ""
            var directionIcon = "I/O Device ↑↓"

            if await isInputOnlyDevice {
                directionIcon = "↓ isInputOnlyDevice"

            } else if await isOutputOnlyDevice {
                directionIcon = "↑ isOutputOnlyDevice"
            }

            let name = " \(name) (\(id))"

            let properties: [Any?] = await [
                "\(aggregateIcon)\(directionIcon)\(name)",
                "UID: \(uid ?? "<nil>")",
                "transportType: \(transportType?.rawValue ?? "<nil>")",
                "nominalSampleRates: \(nominalSampleRates ?? [])",
                "owning device id: \(owningDevice?.id ?? 0)",
                "manufacturer: \(manufacturer ?? "<nil>")",
                "modelUID: \(modelUID ?? "<nil>")",
                "relatedDevices: \(relatedDevices ?? [])",
                "controlList: \(controlList ?? [])",
                "isHidden: \(isHidden)",
                "ownedObjectIDs: \(ownedObjectIDs ?? [])",
            ]

            var ioItems: [Any?] = ["\n"]
            ioItems += await channelsDescription(scope: .input)
            ioItems += await channelsDescription(scope: .output)

            if ioItems.isEmpty {
                ioItems = ["\n\t\t[No IO info available]]"]
            }

            var aggregateItems: [String] = []

            if let value = await ownedAggregateInputDevices, value.isNotEmpty {
                aggregateItems += ["\townedAggregateInputDevices:"]
                aggregateItems += value.map { "\t\t" + $0.description }
            }

            if let value = await ownedAggregateOutputDevices, value.isNotEmpty {
                aggregateItems += ["\townedAggregateOutputDevices:"]
                aggregateItems += value.map { "\t\t" + $0.description }
            }

            let content = (properties.compactMap {
                String(describing: $0 ?? "nil")
            }).joined(separator: ", ")

            let ioContent = (ioItems.compactMap {
                String(describing: $0 ?? "nil")
            }).joined(separator: " ")

            return content + ioContent + aggregateItems.joined(separator: "\n")
        }
    }

    private func channelsDescription(scope: Scope) async -> [Any?] {
        guard await physicalChannels(scope: scope) > 0 else { return [] }

        let names = await namedChannels(scope: scope).map(\.description).joined(separator: ", ")

        let icon = scope == .input ? "↓" : "↑"

        return await [
            "\(icon) \(scope.title)........\n",
            "\t\(physicalChannels(scope: scope)) channel, [\(names)]", "\n",
            "\tdataSources:", dataSources(scope: scope) as Any, "\n",
            "\tpreferredChannelsForStereo:", preferredChannelsForStereo(scope: scope) as Any?, "\n",
            "\tpresentationLatency:", presentationLatency(scope: scope) as Any?, "\n",
        ]
    }
}
