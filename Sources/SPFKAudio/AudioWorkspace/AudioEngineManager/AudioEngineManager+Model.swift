import AVFoundation
import SPFKUtils
import SPFKUtilsC

extension AudioEngineManager: AudioEngineManagerModel {
    public var systemFormat: AVAudioFormat? {
        deviceManager?.systemFormat
    }

    public var allowInput: Bool { deviceManager?.allowInput == true }

    /// Don't access the engine.inputNode if input is disabled as the node is lazily created.
    /// This is the only point in the codebase where AVAudioEngine's inputNode is referenced
    public var inputNode: AVAudioInputNode? {
        guard allowInput else { return nil }
        return engine.inputNode
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

        var error: Error?

        ExceptionCatcherOperation({ [weak self] in
            guard let self else { return }

            engine.connectAndAttach(node1, to: node2, format: format)

        }, { exception in
            Log.error(exception)
            error = NSError(description: exception.debugDescription, code: exception.error.code)
        })

        if let error {
            throw error
        }
    }
}
