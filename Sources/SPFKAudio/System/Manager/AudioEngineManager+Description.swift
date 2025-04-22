
import AVFoundation
import SimplyCoreAudio
import SPFKUtils

// Mostly for debugging purposesF

extension AudioEngineManager {
    public var engineDeviceDescription: String {
        guard let device = deviceManager.engineDevice else {
            return "Failed to find engine device"
        }

        return deviceDescription(device)
    }

    public var description: String {
        var string = ""
        string += "Engine isRunning: \(engineIsRunning)\n"

        string += "↑ Selected Output Device: \(deviceManager.selectedOutputDevice?.name ?? "No Output") @ \(deviceManager.selectedOutputDevice?.actualSampleRate ?? 0) Hz, \(deviceManager.numberOfOutputChannels) Channel\n"

        if let selectedInputDevice = deviceManager.selectedInputDevice {
            string += "↓ Selected Input Device: \(selectedInputDevice.name) @ \(selectedInputDevice.actualSampleRate ?? 0) Hz, \(deviceManager.numberOfInputChannels) Channel\n\n"
        } else {
            string += "↓ Input Device: Disabled or no device detected on this system. ⚠️\n\n"
        }

        string += engineDeviceDescription + "\n"

        string += "\n"

        let outputDevices = deviceManager.allOutputDevices.map { $0.name }.sorted()
        string += "↑ Output Devices: " + outputDevices.joined(separator: ", ")
        string += "\n"

        let inputDevices = deviceManager.allInputDevices.map { $0.name }.sorted()
        string += "↓ Input Devices: " + inputDevices.joined(separator: ", ")
        string += "\n\n"

        string += "outputNode outputFormat → \(engine.outputNode.outputFormat(forBus: 0).readableDescription)\n"
        string += "outputNode inputFormat ← \(engine.outputNode.inputFormat(forBus: 0).readableDescription)\n\n"

        if let inputNode {
            string += "inputNode → \(inputNode.outputFormat(forBus: 0).readableDescription)\n"
            string += "inputNode ← \(inputNode.inputFormat(forBus: 0).readableDescription)\n\n"
        }

        // 84 attached nodes:
        // AVAudioUnitEffect (36), AVAudioOutputNode (1), AVAudioPlayerNode (32)...
        let sampleRates = engine.attachedNodes.map {
            $0.outputFormat(forBus: 0).sampleRate
        }.removingDuplicatesRandomOrdering().sorted()

        string += "Sample Rates: \(sampleRates)\n"

        if sampleRates.count > 1 {
            string += "⚠️ Mixed Sample Rates detected\n\n"
        }

        string += "\(engine.attachedNodes.count) attached node\(engine.attachedNodes.pluralString):\n"
        let classNames = engine.attachedNodes.map { $0.className }
        string += classNames.elementQuantity.map({ "\($0.key) (\($0.value))" }).joined(separator: ", ")
        string += "\n\n"

        string += engine.debugDescription
        return string
    }

    public var debugDescription: String {
        engine.debugDescription
    }

    public func deviceDescription(_ device: AudioDevice) -> String {
        let isSelectedOutputDevice = device == deviceManager.selectedOutputDevice
        let isSelectedInputDevice = device == deviceManager.selectedInputDevice

        let aggregateIcon = device.isAggregateDevice ? "👥 (Aggregate) " : ""

        var directionIcon = "I/O Device ↑↓"

        if device.isInputOnlyDevice {
            directionIcon = "↓ isInputOnlyDevice"

        } else if device.isOutputOnlyDevice {
            directionIcon = "↑ isOutputOnlyDevice"
        }

        let selectedInputIcon = isSelectedInputDevice ? " 🤚 isSelectedInputDevice" : ""
        let selectedOutputIcon = isSelectedOutputDevice ? " 🤚 isSelectedOutputDevice" : ""
        let name = " \(device.name) (\(device.id))"

        let properties: [Any?] = [
            "\(aggregateIcon)\(directionIcon)\(name)\(selectedInputIcon)\(selectedOutputIcon)",
            "UID: \(device.uid ?? "<nil>")",
            "transportType: \(device.transportType?.rawValue ?? "<nil>")",
            "nominalSampleRates: \(device.nominalSampleRates ?? [])",
            "owning device id: \(device.owningDevice?.id ?? 0)",
            "manufacturer: \(device.manufacturer ?? "<nil>")",
            "modelUID: \(device.modelUID ?? "<nil>")",
            "relatedDevices: \(device.relatedDevices ?? [])",
            "controlList: \(device.controlList ?? [])",
            "isHidden: \(device.isHidden)",
            "ownedObjectIDs: \(device.ownedObjectIDs ?? [])",
        ]

        var ioItems: [Any?] = ["\n"]
        ioItems += channelsDescription(device: device, scope: .input)
        ioItems += channelsDescription(device: device, scope: .output)

        if ioItems.isEmpty {
            ioItems = ["\n\t\t[No IO info available]]"]
        }

        var aggregateItems: [String] = []

        if let value = device.ownedAggregateInputDevices, value.isNotEmpty {
            aggregateItems += ["\townedAggregateInputDevices:"]
            aggregateItems += value.map { "\t\t" + deviceDescription($0) }
        }

        if let value = device.ownedAggregateOutputDevices, value.isNotEmpty {
            aggregateItems += ["\townedAggregateOutputDevices:"]
            aggregateItems += value.map { "\t\t" + deviceDescription($0) }
        }

        let content = (properties.compactMap {
            String(describing: $0 ?? "nil")
        }).joined(separator: ", ")

        let ioContent = (ioItems.compactMap {
            String(describing: $0 ?? "nil")
        }).joined(separator: " ")

        return content + ioContent + aggregateItems.joined(separator: "\n")
    }

    func channelsDescription(device: AudioDevice, scope: Scope) -> [Any?] {
        guard device.channels(scope: scope) > 0 else { return [] }

        let names = device.namedChannels(scope: scope).map({ $0.description }).joined(separator: ", ")

        let icon = scope == .input ? "↓" : "↑"

        return [
            "\(icon) \(scope.title)........\n",
            "\t\(device.channels(scope: scope)) channel, [\(names)]", "\n",
            "\tdataSources:", device.dataSources(scope: scope) as Any, "\n",
            "\tpreferredChannelsForStereo:", device.preferredChannelsForStereo(scope: scope) as Any?, "\n",
            "\tpresentationLatency:", device.presentationLatency(scope: scope) as Any?, "\n",
        ]
    }

    func ioNodeDescription(_ node: AVAudioIONode) -> String {
        let inputFormat = node.inputFormat(forBus: 0)
        let outputPresentationLatency = node.outputPresentationLatency
        let presentationLatency = node.presentationLatency
        let latency = node.latency

        let items: [Any?] = [
            node.description,
            "inputFormat", inputFormat,
            "latency", latency,
            "presentationLatency", presentationLatency,
            "outputPresentationLatency", outputPresentationLatency,
        ]

        let content = (items.compactMap {
            String(describing: $0 ?? "nil")
        }).joined(separator: ", ")

        return content
    }
}
