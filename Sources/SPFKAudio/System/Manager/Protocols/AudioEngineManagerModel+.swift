import AVFoundation
import Foundation
import SimplyCoreAudio
import SPFKUtils

// MARK: - Convenience

extension AudioEngineManagerModel {
    public func connectAndAttach(
        _ engineNode: any EngineNode,
        to otherEngineNode: any EngineNode, format: AVAudioFormat? = nil
    ) throws {
        guard let sourceNode = engineNode.outputNode else {
            throw NSError(description: "sourceNode must be valid")
        }

        guard let destinationNode = otherEngineNode.inputNode else {
            throw NSError(description: "destinationNode must be valid")
        }

        try connectAndAttach(sourceNode, to: destinationNode, format: format)
    }

    public func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode) throws {
        try connectAndAttach(node1, to: node2, format: systemFormat)
    }
}

extension AudioEngineManagerModel {
    /// The engine's singleton output node.
    public func setEngineOutput(to node: AVAudioNode) throws {
        if engineIsRunning { stopEngine() }

        try connectAndAttach(node, to: outputNode, format: systemFormat)

        Log.debug("🔈 Output Node:", outputNode,
                  "outputFormat:", outputFormat,
                  "inputFormat:", inputFormat,
                  "systemFormat", systemFormat)
    }
}

// MARK: Formats

extension AudioEngineManagerModel {
    /// Files will render at 32bit PCM then convert after
    public var renderFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: systemFormat.sampleRate,
            channels: systemFormat.channelCount,
            interleaved: true
        )
    }

    public var inputFormat: AVAudioFormat? {
        guard let inputNode else { return nil }

        // accessing this inputNode will lazy create it
        return inputNode.outputFormat(forBus: 0)
    }

    public var allowInput: Bool { inputFormat != nil }

    public var outputFormat: AVAudioFormat {
        outputNode.outputFormat(forBus: 0)
    }

    public var engineIsRunning: Bool {
        engine.isRunning
    }
}
