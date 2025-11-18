import AVFoundation
import Foundation
import SPFKAudioHardware
import SPFKUtils

extension AudioEngineManagerModel {
    /// The engine's singleton output node.
    public func setEngineOutput(to node: AVAudioNode) throws {
        if engineIsRunning { stopEngine() }

        try connectAndAttach(node, to: outputNode, format: systemFormat)
    }
}

// MARK: Formats

extension AudioEngineManagerModel {
    /// Files will render at 32bit PCM then convert after
    public var renderFormat: AVAudioFormat? {
        guard let systemFormat else {
            Log.error("Unable to determine System format")
            return nil
        }

        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: systemFormat.sampleRate,
            channels: systemFormat.channelCount,
            interleaved: true
        )
    }

    public var inputFormat: AVAudioFormat? {
        get async {
            guard let inputNode = await inputNode else { return nil }

            // accessing this inputNode will lazy create it
            return inputNode.outputFormat(forBus: 0)
        }
    }

    public var allowInput: Bool {
        get async {
            await inputFormat != nil
        }
    }

    public var outputFormat: AVAudioFormat {
        outputNode.outputFormat(forBus: 0)
    }

    public var engineIsRunning: Bool {
        engine.isRunning
    }
}
