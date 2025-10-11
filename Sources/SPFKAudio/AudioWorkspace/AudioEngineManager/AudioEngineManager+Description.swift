
import AVFoundation
import SimplyCoreAudio
import SPFKUtils

// Mostly for debugging purposes

extension AudioEngineManager {
    public var engineDeviceDescription: String {
        guard let device = deviceManager?.engineDevice else {
            return "Failed to find engine device"
        }

        return deviceDescription(device)
    }

    public var description: String {
        guard let deviceManager else {
            return "Device Manager isn't available"
        }

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
        guard let deviceManager else {
            return "Device Manager isn't available"
        }

        let isSelectedOutputDevice = device == deviceManager.selectedOutputDevice
        let isSelectedInputDevice = device == deviceManager.selectedInputDevice

        let selectedInputIcon = isSelectedInputDevice ? "🤚 isSelectedInputDevice " : ""
        let selectedOutputIcon = isSelectedOutputDevice ? "🤚 isSelectedOutputDevice " : ""

        let content = "\(selectedInputIcon)\(selectedOutputIcon)\n"

        return content + device.detailedDescription
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
