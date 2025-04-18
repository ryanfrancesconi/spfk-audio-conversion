import AVFoundation
import SimplyCoreAudio
import SPFKUtils
import SPFKUtilsC

extension AudioEngineManager: AudioEngineManagerModel {
    public var engine: AVAudioEngine { _engine }

    public var systemFormat: AVAudioFormat {
        get { deviceManager.systemFormat }
        set {
            deviceManager.systemFormat = newValue
        }
    }

    public var allowInput: Bool { deviceManager.allowInput }

    /// Don't access the engine.inputNode if input is disabled as the node is created on demand.
    /// This is the only point in the ADD codebase where the AVAudioEngine inputNode is referenced
    public var inputNode: AVAudioInputNode? {
        guard allowInput else { return nil }
        return engine.inputNode
    }

    public var outputNode: AVAudioOutputNode { engine.outputNode }

    public func connectAndAttach(
        _ node1: AVAudioNode,
        to node2: AVAudioNode,
        format: AVAudioFormat? = nil
    ) throws {
        //
        let format = format ?? systemFormat

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

    /// Render the contents of the engine to file
    /// `prerender` is the block containing play commands
    /// `postrender` is an optional block to call when duration has been rendered.
    /// Can call stop() in this block
    public func render(
        to audioFile: AVAudioFile,
        duration: Double,
        renderUntilSilent: Bool,
        prerender: (() -> Void)?,
        postrender: (() -> Void)?,
        progress progressHandler: ((ProgressValue1) -> Void)?
    ) throws {
        try renderer.render(
            engine: engine,
            to: audioFile,
            maximumFrameCount: 4096,
            duration: duration,
            renderUntilSilent: renderUntilSilent,
            silenceThreshold: 0.00005,
            prerender: prerender,
            postrender: postrender,
            progress: progressHandler
        )

        if !allowInput {
            // only needed if the engine outputNode is being set to a different device than the default one
            // this is also triggered by the engine configuration notification event
            do {
                try deviceManager.reconnectNodeOutput()
            } catch {
                Log.error(error)
                return
            }
        }

        try startEngine()
    }

    public func cancelRender() {
        guard !renderIsCanceled else { return }

        renderer.cancel()
    }

    public var renderIsCanceled: Bool { renderer.isCanceled }
}
