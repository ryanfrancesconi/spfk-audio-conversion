import Foundation
import SPFKAudioHardware

extension AudioDeviceManager {
    #warning("UPDATE")
    public var description: String {
        var string = ""

        /*
        string += "↑ Selected Output Device: \(selectedOutputDevice?.name ?? "No Output") @ \(selectedOutputDevice?.actualSampleRate ?? 0) Hz, \(numberOfOutputChannels) Channel\n"

        if let selectedInputDevice = selectedInputDevice {
            string += "↓ Selected Input Device: \(selectedInputDevice.name) @ \(selectedInputDevice.actualSampleRate ?? 0) Hz, \(numberOfInputChannels) Channel\n\n"
        } else {
            string += "↓ Input Device: Disabled or no device detected on this system. ⚠️\n\n"
        }

        if let engineDevice {
            string += deviceDescription(engineDevice) + "\n"
        }

        string += "\n"

        let outputDevices = allOutputDevices.map { $0.name }.sorted()
        string += "↑ Output Devices: " + outputDevices.joined(separator: ", ")
        string += "\n"

        let inputDevices = allInputDevices.map { $0.name }.sorted()
        string += "↓ Input Devices: " + inputDevices.joined(separator: ", ")
        string += "\n\n"
        */
        
        return string
    }

    public func deviceDescription(_ device: AudioDevice) -> String {
        /*
        let isSelectedOutputDevice = device == selectedOutputDevice
        let isSelectedInputDevice = device == selectedInputDevice

        let selectedInputIcon = isSelectedInputDevice ? "🤚 isSelectedInputDevice " : ""
        let selectedOutputIcon = isSelectedOutputDevice ? "🤚 isSelectedOutputDevice " : ""

        let content = "\(selectedInputIcon)\(selectedOutputIcon)\n"

        return content + device.detailedDescription
         */
        ""
    }
}

extension AudioDevice {
    public var detailedDescription: String {
        /*
        let aggregateIcon = isAggregateDevice ? " (Aggregate) " : ""
        var directionIcon = "I/O Device ↑↓"

        if isInputOnlyDevice {
            directionIcon = "↓ isInputOnlyDevice"

        } else if isOutputOnlyDevice {
            directionIcon = "↑ isOutputOnlyDevice"
        }

        let name = " \(name) (\(id))"

        let properties: [Any?] = [
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
        ioItems += channelsDescription(scope: .input)
        ioItems += channelsDescription(scope: .output)

        if ioItems.isEmpty {
            ioItems = ["\n\t\t[No IO info available]]"]
        }

        var aggregateItems: [String] = []

        if let value = ownedAggregateInputDevices, value.isNotEmpty {
            aggregateItems += ["\townedAggregateInputDevices:"]
            aggregateItems += value.map { "\t\t" + $0.description }
        }

        if let value = ownedAggregateOutputDevices, value.isNotEmpty {
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
         */
        ""
    }

    private func channelsDescription(scope: Scope) -> [Any?] {
        /*
        guard channels(scope: scope) > 0 else { return [] }

        let names = namedChannels(scope: scope).map({ $0.description }).joined(separator: ", ")

        let icon = scope == .input ? "↓" : "↑"

        return [
            "\(icon) \(scope.title)........\n",
            "\t\(channels(scope: scope)) channel, [\(names)]", "\n",
            "\tdataSources:", dataSources(scope: scope) as Any, "\n",
            "\tpreferredChannelsForStereo:", preferredChannelsForStereo(scope: scope) as Any?, "\n",
            "\tpresentationLatency:", presentationLatency(scope: scope) as Any?, "\n",
        ]
         */
        return []
    }
}
