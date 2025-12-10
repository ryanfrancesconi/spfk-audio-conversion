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
        options: EngineRendererOptions = .init(),
        prerender: @escaping (@Sendable () throws -> Void),
        postrender: (@Sendable () throws -> Void)?,
        progressHandler: (@Sendable (UnitInterval) -> Void)?,
        disableManualRenderingModeOnCompletion: Bool
    ) async throws {
        guard let engine else {
            throw NSError(description: "engine is nil")
        }
        
        let renderer = EngineRenderer(engine: engine)
        self.renderer = renderer
        
        try await renderer.render(
            to: audioFile,
            duration: duration,
            options: options,
            prerender: prerender,
            postrender: postrender,
            progressHandler: progressHandler,
            disableManualRenderingModeOnCompletion: disableManualRenderingModeOnCompletion
        )

        try startEngine()
        self.renderer = nil
    }

    public func cancelRender() async {
        await renderer?.cancelRender()
    }
}
