import AVFoundation
import SPFKUtils
import SPFKUtilsC

extension AudioEngineManager {
    public func prepareEngine() {
        guard !engineIsRunning else { return }

        // engine.prepare()
        Log.debug("🔈 engine.prepare()")

        ExceptionCatcherOperation({
            self.engine.prepare()
        }, { exception in
            Log.error(exception)
        })
    }

    // TODO: REFACTOR: does this need to be on main?

    /// Starts the AVAudioEngine. Will return async to main if the engine wasn't started or
    /// immediately if it is already running
    /// - Parameter completionHandler: handler to call on start
    public func startEngine() throws {
        guard !engineIsRunning else { return }

        Log.debug("🔈 Attempting to start engine with outputFormat", outputFormat, "inputFormat", inputFormat)

        var engineError: Error?

        ExceptionCatcherOperation({
            do {
                self.engine.prepare()
                try self.engine.start()

            } catch {
                engineError = error
            }
        }, { exception in
            engineError = NSError(description: exception.debugDescription)
        })

        if let engineError {
            throw engineError
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

    public func rebuildEngine() {
        removeEngineObserver()

        Log.debug("🔈 Creating new Engine...")

        engine = AVAudioEngine()
        engine.isAutoShutdownEnabled = false

        // The engine creates a singleton on demand when this property is first accessed.
        _ = outputNode

        delegate?.audioEngineManager(event: .rebuild)

        do {
            try deviceManager?.reconnect()

        } catch {
            Log.error(error)
        }

        addEngineObserver()
    }
}
