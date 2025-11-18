
import AVFoundation
import SPFKAudioHardware
import SPFKUtils

// Mostly for debugging purposes

extension AudioEngineManager: CustomStringConvertible {
    public var description: String {
        var string = ""
        string += "Engine isRunning: \(engineIsRunning)\n"

        string += "outputNode outputFormat → \(engine.outputNode.outputFormat(forBus: 0).readableDescription)\n"
        string += "outputNode inputFormat ← \(engine.outputNode.inputFormat(forBus: 0).readableDescription)\n\n"

//        if let inputNode {
//            string += "inputNode → \(inputNode.outputFormat(forBus: 0).readableDescription)\n"
//            string += "inputNode ← \(inputNode.inputFormat(forBus: 0).readableDescription)\n\n"
//        }

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

    // unused
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
