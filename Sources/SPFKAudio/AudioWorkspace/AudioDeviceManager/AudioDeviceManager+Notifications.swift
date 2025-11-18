import Foundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManager {
    @MainActor func send(event: Event) async {
        await delegate?.audioDeviceManager(event: event)
    }

    func removeHardwareObservers() {
        hardwareObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }

        hardwareObservers.removeAll()
    }

    /// Listen for notifications from SimplyCoreAudio
    func addHardwareObservers() {
        removeHardwareObservers()

        hardwareObservers = [
            NotificationCenter.default.addObserver(
                forName: .deviceListChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in

                guard let hardwareNotification = notification.object as? AudioHardwareNotification else { return }
                guard let self else { return }

                guard case let .deviceListChanged(event: event) = hardwareNotification else {
                    return
                }

                // ignore the AVAudioEngine aggregate

                let added = event.addedDevices.filter { !self.isEngineDefaultAggregate(device: $0) }
                let removed = event.removedDevices.filter { !self.isEngineDefaultAggregate(device: $0) }

                guard added.isNotEmpty || removed.isNotEmpty else { return }

                Task {
                    await self.send(event: .deviceListChanged(
                        addedDevices: added,
                        removedDevices: removed)
                    )
                }
            },

            NotificationCenter.default.addObserver(
                forName: .defaultInputDeviceChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in

                guard let self else { return }

                guard case .defaultInputDeviceChanged = notification.object as? AudioHardwareNotification else {
                    return
                }

                Task {
                    guard await self.allowInput else {
                        Log.debug("Can ignore this event")
                        return
                    }

                    guard let defaultInputDevice = await self.defaultInputDevice else { return }

                    guard defaultInputDevice.uid != self.deviceSettings.inputUID else {
                        Log.debug("Same device is already selected", defaultInputDevice)
                        return
                    }

                    await self.send(event: .inputDeviceChanged(device: defaultInputDevice))
                }

            },

            NotificationCenter.default.addObserver(
                forName: .defaultOutputDeviceChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard case .defaultOutputDeviceChanged = notification.object as? AudioHardwareNotification else {
                    return
                }

                Task {
                    guard await self.allowInput else {
                        Log.debug("Can ignore this defaultOutputDeviceChanged")
                        return
                    }

                    guard let defaultOutputDevice = await self.defaultOutputDevice else {
                        Log.error(notification.object)
                        assertionFailure()
                        return
                    }

                    guard defaultOutputDevice.uid != self.deviceSettings.outputUID else {
                        Log.debug("Same device is already selected", defaultOutputDevice)
                        return
                    }

                    await self.send(event: .outputDeviceChanged(device: defaultOutputDevice))
                }

            },

            NotificationCenter.default.addObserver(
                forName: .deviceProcessorOverload,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { await self?.send(event: .deviceProcessorOverload) }
            },
        ]
    }
}

extension AudioDeviceManager {
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
    func addInputDeviceObserver(for device: AudioDevice) async {
        removeInputDeviceObserver()

        guard await allowInput else { return }
        guard let sampleRate = device.nominalSampleRate else { return }

        inputDeviceObserver = NotificationCenter.default.addObserver(
            forName: .deviceNominalSampleRateDidChange,
            object: device,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            Task {
                let selectedInputDevice = await self.selectedInputDevice

                guard let notificationDevice = notification.object as? AudioDevice,
                      notificationDevice == selectedInputDevice else {
                    return
                }

                Log.debug("🎤 deviceNominalSampleRateDidChange to", sampleRate)

                await self.send(event: .sampleRateChanged(sampleRate))
            }
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

            Task {
                let selectedOutputDevice = await self.selectedOutputDevice

                guard let notificationDevice = notification.object as? AudioDevice,
                      notificationDevice == selectedOutputDevice else {
                    return
                }

                Log.debug("🎧 deviceNominalSampleRateDidChange", device.name, "to", device.nominalSampleRate)

                guard let sampleRate = device.nominalSampleRate else { return }
                await self.send(event: .sampleRateChanged(sampleRate))
            }
        }
    }
}

extension AudioDeviceManager {
    public func handleEngineConfigurationChanged() async {
        guard let selectedOutputDevice = await selectedOutputDevice,
              let outputDeviceSampleRate = await outputDeviceSampleRate else {
            return
        }

        guard AudioDefaults.isSupported(sampleRate: outputDeviceSampleRate) else {
            let errorEvent: Event = .error(
                NSError(description: "\(selectedOutputDevice.name) is set to an incompatible sample rate of \(outputDeviceSampleRate)")
            )

            await send(event: errorEvent)
            return
        }

        let outputDeviceChanged = selectedOutputDevice.uid != deviceSettings.outputUID
        let inputDeviceChanged = await selectedInputDevice?.uid != deviceSettings.inputUID

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

        await send(event: .configurationChanged(options))
    }
}
