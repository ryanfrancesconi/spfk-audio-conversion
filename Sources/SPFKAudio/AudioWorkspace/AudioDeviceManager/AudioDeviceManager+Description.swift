import Foundation
import SPFKAudioHardware

extension AudioDeviceManager {
    public var detailedDescription: String {
        get async {
            var string = ""

            string += "↑ Selected Output Device: \(await selectedOutputDevice?.name ?? "No Output") @ \(await selectedOutputDevice?.actualSampleRate ?? 0) Hz, \(await numberOfOutputChannels) Channel\n"

            if let selectedInputDevice = await selectedInputDevice {
                string += "↓ Selected Input Device: \(selectedInputDevice.name) @ \(selectedInputDevice.actualSampleRate ?? 0) Hz, \(await numberOfInputChannels) Channel\n\n"
            } else {
                string += "↓ Input Device: Disabled or no device detected on this system. ⚠️\n\n"
            }

            if let engineDevice = await engineDevice {
                await string += deviceDescription(engineDevice) + "\n"
            }

            string += "\n"

            let outputDevices = await outputDevices.map { $0.name }.sorted()
            string += "↑ Output Devices: " + outputDevices.joined(separator: ", ")
            string += "\n"

            let inputDevices = await inputDevices.map { $0.name }.sorted()
            string += "↓ Input Devices: " + inputDevices.joined(separator: ", ")
            string += "\n\n"

            return string
        }
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

            let properties: [Any?] = [
                "\(aggregateIcon)\(directionIcon)\(name)",
                "UID: \(uid ?? "<nil>")",
                "transportType: \(transportType?.rawValue ?? "<nil>")",
                "nominalSampleRates: \(nominalSampleRates ?? [])",
                "owning device id: \(await owningDevice?.id ?? 0)",
                "manufacturer: \(manufacturer ?? "<nil>")",
                "modelUID: \(modelUID ?? "<nil>")",
                "relatedDevices: \(await relatedDevices ?? [])",
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
        guard await channels(scope: scope) > 0 else { return [] }

        let names = await namedChannels(scope: scope).map({ $0.description }).joined(separator: ", ")

        let icon = scope == .input ? "↓" : "↑"

        return [
            "\(icon) \(scope.title)........\n",
            "\t\(await channels(scope: scope)) channel, [\(names)]", "\n",
            "\tdataSources:", dataSources(scope: scope) as Any, "\n",
            "\tpreferredChannelsForStereo:", preferredChannelsForStereo(scope: scope) as Any?, "\n",
            "\tpresentationLatency:", await presentationLatency(scope: scope) as Any?, "\n",
        ]
    }
}
