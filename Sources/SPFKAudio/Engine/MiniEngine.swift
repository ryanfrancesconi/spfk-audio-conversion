import SPFKUtils

/// A small engine for playback tests
public class MiniEngine {
    public let manager = AudioEngineManager()
    public let mixer = MixerWrapper()

    public init() throws {
        guard let outputNode = mixer.outputNode else {
            throw NSError(description: "outputNode is nil")
        }

        try manager.setEngineOutput(to: outputNode)
    }

    public func start() throws {
        try manager.startEngine()
    }

    public func connect(node: any EngineNode) throws {
        guard let avNode = node.outputNode else {
            throw NSError(description: "node's outputNode is nil")
        }

        try manager.connectAndAttach(avNode, to: mixer.avAudioNode)
    }
}
