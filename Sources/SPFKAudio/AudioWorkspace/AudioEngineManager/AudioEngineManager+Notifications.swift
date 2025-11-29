import AVFoundation
import Foundation
import SPFKBase

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parse(notification:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    func removeEngineObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }
}

extension AudioEngineManager {
    @MainActor @objc private func parse(notification: Notification) {
        Log.debug(notification)

        Task {
            await send(event: .configurationChanged)
        }
    }
}
