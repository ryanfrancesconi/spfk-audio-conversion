import AVFoundation
import SPFKBase
import SPFKBaseC

extension AudioEngineManager {
    public func prepareEngine() throws {
        guard !engineIsRunning else { return }

        guard let engine else { return }

        Log.debug("🔈 engine.prepare()")

        try ExceptionTrap.withThrowing { [engine] in
            engine.prepare()
        }
    }

    // TODO: REFACTOR: does this need to be on main?

    /// Starts the AVAudioEngine. Will return async to main if the engine wasn't started or
    /// immediately if it is already running
    /// - Parameter completionHandler: handler to call on start
    public func startEngine() throws {
        guard let engine else { return }

        guard !engineIsRunning else { return }

        Log.debug("🔈 Attempting to start engine with outputFormat", outputFormat)
        // Log.debug("🔈", engine.debugDescription)

        try ExceptionTrap.withThrowing { [engine] in
            engine.prepare()
            try engine.start()
        }
    }

    public func stopEngine() {
        guard let engine else { return }

        guard engineIsRunning else { return }

        engine.stop()
        Log.debug("🔈 Engine is stopped")
    }

    public func pauseEngine() {
        guard let engine else { return }

        engine.pause()
        Log.debug("🔈 Engine is paused")
    }

    public func resetEngine() {
        guard let engine else { return }

        engine.reset()
    }

    public func rebuildEngine() async {
        await delegate.audioEngineManager(event: .willRebuild)

        stopEngine()
        removeEngineObserver()

        Log.debug("🔈 Creating new Engine...")

        let engine = AVAudioEngine()
        engine.isAutoShutdownEnabled = false

        self.engine = engine

        // The engine creates a singleton on demand when this property is first accessed.
        _ = engine.outputNode

        addEngineObserver()

        await delegate.audioEngineManager(event: .didRebuild)
    }
}
