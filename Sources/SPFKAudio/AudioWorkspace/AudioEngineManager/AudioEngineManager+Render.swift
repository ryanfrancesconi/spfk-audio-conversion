import AVFoundation
import SPFKBase

extension AudioEngineManager: EngineRendererModel {
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
        progress progressHandler: ((UnitInterval) -> Void)?
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

//        if !allowInput {
//            // only needed if the engine outputNode is being set to a different device than the default one
//            // this is also triggered by the engine configuration notification event
//            do {
//                try deviceManager?.reconnectNodeOutput()
//            } catch {
//                Log.error(error)
//                return
//            }
//            
//        }

        // send event engine mode switched, offline realtime
        
        try startEngine()
    }

    public func cancelRender() {
        guard !renderIsCanceled else { return }

        renderer.cancel()
    }

    public var renderIsCanceled: Bool { renderer.isCanceled }
}
