// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public protocol NodeOutputAccess: AnyObject {
    var outputNode: AVAudioNode? { get }
}

public protocol NodeInputAccess: AnyObject {
    var inputNode: AVAudioNode? { get }
}

public protocol EngineNode: NodeInputAccess, NodeOutputAccess {
    var isBypassed: Bool { get set }
    func detachNodes() throws
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
            Log.error("\(self) \(#function): engine is nil")
            return false
        }

        return outputNode.isOutputNodeConnected
    }

    public var format: AVAudioFormat? {
        outputNode?.outputFormat(forBus: 0)
    }

    public var engine: AVAudioEngine? {
        outputNode?.engine ?? inputNode?.engine
    }

    public var engineFormat: AVAudioFormat? {
        engine?.outputFormat
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

    /// Default behavior is to only detach the IO nodes.
    /// Can be implemented for custom handling
    public func detachNodes() throws {
        try detachIONodes()
    }

    public func detachIONodes() throws {
        guard let engine else {
            throw NSError(description: "\(self) \(#function): engine is nil")
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
