// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public protocol AudioEngineConnection: AnyObject {
    func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) throws
}

extension AudioEngineConnection {
    public func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode) throws {
        try connectAndAttach(node1, to: node2, format: nil) // use systemFormat
    }

    public func connectAndAttach(
        _ engineNode: any EngineNode,
        to otherEngineNode: any EngineNode,
        format: AVAudioFormat? = nil
    ) throws {
        guard let sourceNode = engineNode.outputNode else {
            throw NSError(description: "engineNode.outputNode must be valid")
        }

        guard let destinationNode = otherEngineNode.inputNode else {
            throw NSError(description: "otherEngineNode.inputNode must be valid")
        }

        try connectAndAttach(sourceNode, to: destinationNode, format: format)
    }
}
