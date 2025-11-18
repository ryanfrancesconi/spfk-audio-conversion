import AVFoundation
import Foundation
import SPFKUtils

extension AudioEngineManager {
    /**
     When the engine's I/O unit observes a change to the audio input or output hardware's
     channel count or sample rate, the engine stops itself (see `AVAudioEngine(stop)`), and
     issues this notification.
     The nodes remain attached and connected with previously set formats. However, the app
     must reestablish connections if the connection formats need to change (e.g. in an
     input node chain, connections must follow the hardware sample rate, while in an output only
     chain, the output node supports rate conversion).

     Note that the engine must not be deallocated from within the client's notification handler
     because the callback happens on an internal dispatch queue and can deadlock while trying to
     synchronously teardown the engine.
     */
    func addEngineObserver() {
        removeEngineObserver()

        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] notification in

            guard let self else { return }

            parse(notification: notification)
        }
    }

    func removeEngineObserver() {
        guard let engineObserver else { return }
        NotificationCenter.default.removeObserver(engineObserver)
        self.engineObserver = nil
    }
}

extension AudioEngineManager {
    private func parse(notification: Notification) {
        guard let notificationEngine = notification.object as? AVAudioEngine,
              engine == notificationEngine else { return }

        Log.debug(notification)

        Task { @MainActor in
            await send(event: .configurationChanged)
        }
    }
}
