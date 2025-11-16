import Foundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManager {
    /// Listen for notifications from SimplyCoreAudio
    func addHardwareObservers() {
        removeHardwareObservers()

        hardwareObservers = [
            // e.g., subscribing to `deviceListChanged` notification.
            NotificationCenter.default.addObserver(
                forName: .deviceListChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }

                guard var addedDevices = notification.userInfo?["addedDevices"] as? [AudioDevice],
                      var removedDevices = notification.userInfo?["removedDevices"] as? [AudioDevice]
                else {
                    return
                }

                // ignore the AVAudioEngine aggregate

                addedDevices = addedDevices.filter { !self.isEngineDefaultAggregate(device: $0) }
                removedDevices = removedDevices.filter { !self.isEngineDefaultAggregate(device: $0) }

                guard addedDevices.isNotEmpty || removedDevices.isNotEmpty else { return }

                self.send(event: .deviceListChanged(
                    addedDevices: addedDevices,
                    removedDevices: removedDevices)
                )
            },

            NotificationCenter.default.addObserver(
                forName: .defaultInputDeviceChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in

                guard let self else { return }

                guard allowInput else {
                    Log.debug("Can ignore this event")
                    return
                }

                guard let defaultInputDevice else { return }

                guard defaultInputDevice.uid != deviceSettings.inputUID else {
                    Log.debug("Same device is already selected", defaultInputDevice)
                    return
                }

                send(event: .inputDeviceChanged(device: defaultInputDevice))

            },

            NotificationCenter.default.addObserver(
                forName: .defaultOutputDeviceChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }

                guard allowInput else {
                    Log.debug("Can ignore this defaultOutputDeviceChanged")
                    return
                }

                guard let defaultOutputDevice else {
                    Log.error(notification.object)
                    assertionFailure()
                    return
                }

                guard defaultOutputDevice.uid != deviceSettings.outputUID else {
                    Log.debug("Same device is already selected", defaultOutputDevice)
                    return
                }

                send(event: .outputDeviceChanged(device: defaultOutputDevice))

            },

            NotificationCenter.default.addObserver(
                forName: .deviceProcessorOverload,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.send(event: .deviceProcessorOverload)
            },
        ]
    }

    func removeHardwareObservers() {
        hardwareObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }

        hardwareObservers.removeAll()
    }

    func removeInputDeviceObserver() {
        if let inputDeviceObserver {
            NotificationCenter.default.removeObserver(inputDeviceObserver)
        }

        inputDeviceObserver = nil
    }

    func removeOutputDeviceObserver() {
        if let outputDeviceObserver {
            NotificationCenter.default.removeObserver(outputDeviceObserver)
        }

        outputDeviceObserver = nil
    }

    /// Add an observer for the currently selected input device
    /// - Parameter device: An input device to watch for sample rate changes
    func addInputDeviceObserver(for device: AudioDevice) {
        removeInputDeviceObserver()

        guard allowInput else { return }

        inputDeviceObserver = NotificationCenter.default.addObserver(
            forName: .deviceNominalSampleRateDidChange,
            object: device,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            guard let notificationDevice = notification.object as? AudioDevice,
                  notificationDevice == selectedInputDevice else {
                return
            }

            Log.debug("🎤 deviceNominalSampleRateDidChange", device.name, "to", device.nominalSampleRate)

            guard let sampleRate = device.nominalSampleRate else { return }

            send(event: .sampleRateChanged(sampleRate))
        }
    }

    /// Add an observer for the currently selected output device
    /// - Parameter device: An output device to watch for sample rate changes
    func addOutputDeviceObserver(for device: AudioDevice) {
        removeOutputDeviceObserver()

        outputDeviceObserver = NotificationCenter.default.addObserver(
            forName: .deviceNominalSampleRateDidChange,
            object: device,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            guard let notificationDevice = notification.object as? AudioDevice,
                  notificationDevice == selectedOutputDevice else {
                return
            }

            Log.debug("🎧 deviceNominalSampleRateDidChange", device.name, "to", device.nominalSampleRate)

            guard let sampleRate = device.nominalSampleRate else { return }
            send(event: .sampleRateChanged(sampleRate))
        }
    }
}

extension AudioDeviceManager {
    public func handleEngineConfigurationChanged() {
        guard let selectedOutputDevice,
              let outputDeviceSampleRate else {
            return
        }

        guard AudioDefaults.isSupported(sampleRate: outputDeviceSampleRate) else {
            let errorEvent: Event = .error(
                NSError(description: "\(selectedOutputDevice.name) is set to an incompatible sample rate of \(outputDeviceSampleRate)")
            )

            send(event: errorEvent)
            return
        }

        let outputDeviceChanged = selectedOutputDevice.uid != deviceSettings.outputUID
        let inputDeviceChanged = selectedInputDevice?.uid != deviceSettings.inputUID

        let sampleRateChanged = outputDeviceSampleRate != systemSampleRate

        var options = Set<ConfigurationOption>()

        if outputDeviceChanged {
            options.insert(.outputDeviceChanged)
        }

        if inputDeviceChanged {
            options.insert(.inputDeviceChanged)
        }

        if sampleRateChanged {
            options.insert(.sampleRateChanged)
        }

        send(event: .configurationChanged(options))
    }
}
