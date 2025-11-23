import AVFoundation
import SPFKAudioBase
import SPFKBaseC
import SPFKUtils

extension AudioEngineManager: AudioEngineManagerModel {
    public var systemFormat: AVAudioFormat? {
        AudioDefaults.systemFormat
    }

    /// Don't access the engine.inputNode if input is disabled as the node is lazily created.
    /// This is the only point in the codebase where AVAudioEngine's inputNode is referenced
    public var inputNode: AVAudioInputNode? {
        get async {
            guard await allowInput else { return nil }
            return engine.inputNode
        }
    }

    public var outputNode: AVAudioOutputNode { engine.outputNode }
}

extension AudioEngineManager: AudioEngineConnection {
    public func connectAndAttach(
        _ node1: AVAudioNode,
        to node2: AVAudioNode,
        format: AVAudioFormat? = nil
    ) throws {
        //
        guard let format = format ?? systemFormat else {
            throw NSError(description: "Unable to determine systemFormat from deviceManager")
        }

        try ExceptionTrap.withThrowing { [weak self] in
            guard let self else { return }

            engine.connectAndAttach(node1, to: node2, format: format)
        }
    }
}
