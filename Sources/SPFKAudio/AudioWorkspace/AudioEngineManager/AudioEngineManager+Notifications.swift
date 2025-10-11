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

            guard let self,
                  let notificationEngine = notification.object as? AVAudioEngine,
                  engine == notificationEngine
            else { return }

            parseNotification()
        }
    }

    func removeEngineObserver() {
        guard let engineObserver else { return }
        NotificationCenter.default.removeObserver(engineObserver)
        self.engineObserver = nil
    }
}

extension AudioEngineManager {
    fileprivate var sampleRateHasChanged: Bool {
        deviceManager?.outputDeviceSampleRate != deviceManager?.systemSampleRate
    }

    private func _send(event: Event) {
        Task { @MainActor in
            self.send(event: event)
        }
    }

    private func parseNotification() {
        guard let selectedOutputDevice = deviceManager?.selectedOutputDevice,
              let outputDeviceSampleRate = deviceManager?.outputDeviceSampleRate else {
            return
        }

        guard outputDeviceSampleRate >= AudioDefaults.minimumSampleRateSupported else {
            let errorEvent: Event = .error(NSError(description: "\(selectedOutputDevice.name) is set to an incompatible sample rate of \(outputDeviceSampleRate)"))
            _send(event: errorEvent)
            return
        }

        let outputDeviceChanged = deviceManager?.selectedOutputDevice?.uid != deviceManager?.deviceSettings.outputUID
        let inputDeviceChanged = deviceManager?.selectedInputDevice?.uid != deviceManager?.deviceSettings.inputUID
        let sampleRateChanged = outputDeviceSampleRate != deviceManager?.systemSampleRate

        _send(
            event: .configuration(
                event: ConfigurationEvent(
                    sampleRateChanged: sampleRateChanged,
                    outputDeviceChanged: outputDeviceChanged,
                    inputDeviceChanged: inputDeviceChanged
                )
            )
        )
    }
}
