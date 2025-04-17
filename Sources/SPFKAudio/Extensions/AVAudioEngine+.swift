import AVFoundation
import SPFKUtils

extension AVAudioEngine {
    public var outputFormat: AVAudioFormat {
        outputNode.outputFormat(forBus: 0)
    }

    public func safeAttach(nodes: [AVAudioNode]) {
        let unattached = nodes.filter { $0.engine == nil }

        unattached.forEach {
            attach($0)
        }
    }

    public func safeDetach(nodes: [AVAudioNode]) {
        let attached = nodes.filter { $0.engine != nil }

        attached.forEach { detach($0) }
    }

    public func connectAndAttach(
        _ node1: AVAudioNode,
        to node2: AVAudioNode,
        format: AVAudioFormat
    ) {
        safeAttach(nodes: [node1, node2])

        // Only an issue if engine is running, node is a mixer, and mixer has no inputs
        if isRunning, let mixerNode = node1 as? AVAudioMixerNode, mixerNode.inputs.isEmpty {
            initialize(mixer: mixerNode, format: format)
        }

        connect(node1, to: node2, format: format)

        // once the mixer has more than 1 input in it, we can get rid of the initialization node
        // yes this is node2
        if let mixerNode = node2 as? AVAudioMixerNode, mixerNode.inputs.count >= 2 {
            detachMixerInitializationNodes(in: mixerNode)
        }
    }

    public func detachMixerInitializationNodes() {
        let nodes = attachedNodes.compactMap { $0 as? MixerInitializationtNode }
        nodes.forEach { $0.disconnectOutput() }
        safeDetach(nodes: nodes)
    }

    public func detachMixerInitializationNodes(in mixer: AVAudioMixerNode) {
        let nodes = mixer.inputs.compactMap {
            $0.node as? MixerInitializationtNode
        }
        nodes.forEach { $0.disconnectOutput() }
        safeDetach(nodes: nodes)
    }
}

extension AVAudioEngine {
    /// This hack only works if the node is left attached until a new input is added.
    /// If an AVAudioMixerNode's output connection is made while engine is running, and there are no input connections
    /// on the mixer, subsequent connections made to the mixer will silently fail.  A workaround is to connect a dummy
    /// node to the mixer prior to making a connection.
    ///
    /// This is still a bug as of macOS 14.6 (2024).
    @discardableResult private func initialize(mixer: AVAudioMixerNode, format: AVAudioFormat) -> MixerInitializationtNode? {
        let dummy = MixerInitializationtNode()

        safeAttach(nodes: [dummy])
        connect(dummy, to: mixer, format: format)

        Log.debug("⚠️🎚 Added reset node \(dummy) to mixer with format \(format)")
        return dummy
    }
}

/// A typed node so we can detect and manage if it leaks
internal class MixerInitializationtNode: AVAudioUnitSampler {
    deinit {
        Log.debug("* { MixerInitializationtNode }")
    }
}
