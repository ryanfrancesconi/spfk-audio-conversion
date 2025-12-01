// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public protocol AudioEngineConnection: Sendable {
    func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) async throws
}

extension AudioEngineConnection {
    public func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode) async throws {
        try await connectAndAttach(node1, to: node2, format: nil) // use systemFormat
    }

    public func connectAndAttach(
        _ engineNode: any EngineNode,
        to otherEngineNode: any EngineNode,
        format: AVAudioFormat? = nil
    ) async throws {
        guard let sourceNode = engineNode.outputNode else {
            throw NSError(description: "engineNode.outputNode must be valid")
        }

        guard let destinationNode = otherEngineNode.inputNode else {
            throw NSError(description: "otherEngineNode.inputNode must be valid")
        }

        try await connectAndAttach(sourceNode, to: destinationNode, format: format)
    }
}
