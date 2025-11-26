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
        prerender: (() throws -> Void)?,
        postrender: (() throws -> Void)?,
        progressHandler: ((UnitInterval) -> Void)?
    ) async throws {
        defer {
            do {
                try startEngine()
            } catch {
                Log.error(error)
            }
        }

        renderer = try EngineRenderer(
            engine: engine,
            to: audioFile,
            duration: duration,
            options: options,
            prerender: prerender,
            postrender: postrender,
            progressHandler: progressHandler
        )

        try await renderer?.start()

        renderer = nil
    }

    public func cancelRender() async {
        await renderer?.cancel()
    }
}
