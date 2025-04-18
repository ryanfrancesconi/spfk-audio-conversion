//  Copyright © 2021 Audio Design Desk. All rights reserved.

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

    func detach() // probably remove this and consolidate with AudioConnectable
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

    public func disconnectInput() {
        inputNode?.disconnectInput()
    }

    public func disconnectOutput() {
        outputNode?.disconnectOutput()
    }

    public func detachNodes() {
        guard let engine else { return }

        if let inputNode {
            inputNode.disconnectInput()
            engine.safeDetach(nodes: [inputNode])
        }

        if let outputNode {
            outputNode.disconnectOutput()
            engine.safeDetach(nodes: [outputNode])
        }
    }
}
