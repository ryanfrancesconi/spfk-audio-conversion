import AVFoundation
import Foundation
import SPFKAudioHardware
import SPFKBase

extension AudioEngineManagerModel {
    /// The engine's singleton output node.
    public func setEngineOutput(to node: AVAudioNode) async throws {
        guard let systemFormat = await systemFormat else {
            throw NSError(description: "Unable to determine System format")
        }

        if engineIsRunning { stopEngine() }

        try await connectAndAttach(node, to: outputNode, format: systemFormat)
    }
}

// MARK: Formats

extension AudioEngineManagerModel {
    /// Files will render at 32bit PCM then convert after
    public var renderFormat: AVAudioFormat? {
        get async {
            guard let systemFormat = await systemFormat else {
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
    }

    public var inputFormat: AVAudioFormat? {
        get async {
            guard let inputNode = await inputNode else { return nil }

            // accessing this inputNode will lazy create it
            return inputNode.outputFormat(forBus: 0)
        }
    }

    public var outputFormat: AVAudioFormat {
        outputNode.outputFormat(forBus: 0)
    }

    public var engineIsRunning: Bool {
        engine.isRunning
    }
}
