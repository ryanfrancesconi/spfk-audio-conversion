import AVFoundation
import SPFKBase
import SPFKBaseC

extension AudioEngineManager {
    public func prepareEngine() throws {
        guard !engineIsRunning else { return }

        Log.debug("🔈 engine.prepare()")

        try ExceptionTrap.withThrowing { [weak self] in
            guard let self else { return }
            engine.prepare()
        }
    }

    // TODO: REFACTOR: does this need to be on main?

    /// Starts the AVAudioEngine. Will return async to main if the engine wasn't started or
    /// immediately if it is already running
    /// - Parameter completionHandler: handler to call on start
    public func startEngine() throws {
        guard !engineIsRunning else { return }

        Log.debug("🔈 Attempting to start engine with outputFormat", outputFormat)
        // Log.debug("🔈", engine.debugDescription)
        
        try ExceptionTrap.withThrowing { [weak self] in
            guard let self else { return }

            engine.prepare()
            try engine.start()
        }
    }

    public func stopEngine() {
        guard engineIsRunning else { return }

        engine.stop()
        Log.debug("🔈 Engine is stopped")
    }

    public func pauseEngine() {
        engine.pause()
        Log.debug("🔈 Engine is paused")
    }

    public func resetEngine() {
        engine.reset()
    }

    public func rebuildEngine() async {
        stopEngine()
        removeEngineObserver()

        Log.debug("🔈 Creating new Engine...")

        //engine = AVAudioEngine()
        engine.isAutoShutdownEnabled = false

        // The engine creates a singleton on demand when this property is first accessed.
        _ = outputNode

        await send(event: .rebuild)
        addEngineObserver()
    }
}
