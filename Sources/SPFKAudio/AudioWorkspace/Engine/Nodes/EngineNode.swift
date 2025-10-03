// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKUtils

public protocol NodeOutputAccess: AnyObject {
    var outputNode: AVAudioNode? { get }
}

public protocol NodeInputAccess: AnyObject {
    var inputNode: AVAudioNode? { get }
}

public protocol EngineNode: NodeInputAccess, NodeOutputAccess {
    var isBypassed: Bool { get set }

    func detach() throws // remove
}

extension EngineNode {
    public var inputNode: AVAudioNode? { nil }
    public var outputNode: AVAudioNode? { nil }

    public var isBypassed: Bool {
        get { false }
        set {}
    }

    public var isOutputNodeConnected: Bool {
        guard let outputNode else {
            Log.error("outputNode is nil")
            return false
        }

        return outputNode.isOutputNodeConnected
    }

    public var format: AVAudioFormat? {
        outputNode?.outputFormat(forBus: 0)
    }

    public var engineFormat: AVAudioFormat? {
        engine?.outputFormat
    }

    public var engine: AVAudioEngine? {
        outputNode?.engine ?? inputNode?.engine
    }

    public var isInManualRenderingMode: Bool {
        engine?.isInManualRenderingMode == true
    }

    public func disconnectInput() throws {
        try inputNode?.disconnectInput()
    }

    public func disconnectOutput() throws {
        try outputNode?.disconnectOutput()
    }

    public func detachNodes() throws {
        guard let engine else {
            throw NSError(description: "\(self) detachNodes: engine is nil")
        }

        if let inputNode {
            try inputNode.disconnectInput()
            engine.safeDetach(nodes: [inputNode])
        }

        if let outputNode, inputNode != outputNode {
            try outputNode.disconnectOutput()
            engine.safeDetach(nodes: [outputNode])
        }
    }
}
