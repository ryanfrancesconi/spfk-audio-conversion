import SPFKUtils
import SPFKUtilsC
import AVFoundation

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
                // Start the engine.
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

        _engine = AVAudioEngine()
        _engine.isAutoShutdownEnabled = false

        // The engine creates a singleton on demand when this property is first accessed.
        _ = outputNode

        do {
            if deviceManager.allowInput {
                ExceptionCatcherOperation({ [weak self] in
                    guard let self else { return }

                    _ = inputNode
                    verifyInputSampleRate()

                }, { exception in
                    Log.error(exception.debugDescription)
                })

            } else {
                try deviceManager.reconnectNodeOutput()
            }

            try deviceManager.updatePreferredOutputChannels()

        } catch {
            Log.error(error)
        }

        addEngineObserver()
    }
}
