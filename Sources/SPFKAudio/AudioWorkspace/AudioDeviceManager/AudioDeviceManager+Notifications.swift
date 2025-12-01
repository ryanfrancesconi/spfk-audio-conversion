import Foundation
import SPFKAudioBase
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManager {
    func send(event: Event) async {
        Log.debug("🔊 \(event)")

        guard let delegate else { return }

        await delegate.audioDeviceManager(event: event)
    }

    func removeHardwareObservers() {
        // Remove any token-based observers we might have stored previously.
        for hardwareObserver in hardwareObservers {
            NotificationCenter.default.removeObserver(hardwareObserver)
        }

        hardwareObservers.removeAll()

        // Also remove selector-based observers registered on self.
        NotificationCenter.default.removeObserver(self, name: .deviceListChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .defaultInputDeviceChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .defaultOutputDeviceChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: .deviceNominalSampleRateDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .deviceProcessorOverload, object: nil)
    }

    func addHardwareObservers() {
        removeHardwareObservers()

        // Use selector-based observers to avoid @Sendable closure captures of `self`.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parse(notification:)),
            name: .deviceListChanged,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parse(notification:)),
            name: .defaultInputDeviceChanged,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parse(notification:)),
            name: .defaultOutputDeviceChanged,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parse(notification:)),
            name: .deviceNominalSampleRateDidChange,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parse(notification:)),
            name: .deviceProcessorOverload,
            object: nil)
    }

    @MainActor
    @objc private func parse(notification: Notification) {
        // Extract a Sendable payload first to avoid capturing Notification/self in a concurrent context.
        if let hardwareNotification = notification.object as? AudioHardwareNotification {
            Task {
                await parse(hardwareNotification: hardwareNotification)
            }
        } else if let deviceNotification = notification.object as? AudioDeviceNotification {
            Task {
                await parse(deviceNotification: deviceNotification)
            }
        }
    }

    private func parse(hardwareNotification: AudioHardwareNotification) async {
        switch hardwareNotification {
        case .defaultSystemOutputDeviceChanged:
            break

        case .defaultInputDeviceChanged:
            guard await allowInput else {
                Log.debug("Can ignore this event")
                return
            }

            guard let defaultInputDevice = await defaultInputDevice else { return }

            guard defaultInputDevice.uid != deviceSettings.inputUID else {
                Log.debug("Same device is already selected", defaultInputDevice)
                return
            }

            await send(event: .inputDeviceChanged(device: defaultInputDevice))

        case .defaultOutputDeviceChanged:
            guard await allowInput else {
                Log.debug("Can ignore this defaultOutputDeviceChanged")
                return
            }

            guard let defaultOutputDevice = await defaultOutputDevice else {
                assertionFailure()
                return
            }

            guard defaultOutputDevice.uid != deviceSettings.outputUID else {
                Log.debug("Same device is already selected", defaultOutputDevice)
                return
            }

            await send(event: .outputDeviceChanged(device: defaultOutputDevice))

        case .deviceListChanged(objectID: _, event: let event):
            let added = event.addedDevices.filter { !Self.isEngineDefaultAggregate(device: $0) }
            let removed = event.removedDevices.filter { !Self.isEngineDefaultAggregate(device: $0) }

            guard added.isNotEmpty || removed.isNotEmpty else { return }

            let filteredEvent = DeviceStatusEvent(
                addedDevices: added,
                removedDevices: removed
            )

            await send(event: .deviceListChanged(event: filteredEvent))
        }
    }

    private func parse(deviceNotification: AudioDeviceNotification) async {
        guard let notificationDevice = await deviceNotification.getAudioDevice() else { return }

        let devices = [
            await selectedInputDevice,
            await selectedOutputDevice,
        ]

        guard devices.contains(notificationDevice) else { return }

        switch deviceNotification {
        case .deviceAvailableNominalSampleRatesDidChange:
            // guard let sampleRate = notificationDevice.nominalSampleRate else { return }
            await send(event: .sampleRateChanged(device: notificationDevice))

        case .deviceProcessorOverload:
            await send(event: .deviceProcessorOverload)

        // more events available...

        default:
            break
        }
    }
}

extension AudioDeviceManager {
    public func handleEngineConfigurationChanged() async {
        guard let selectedOutputDevice = await selectedOutputDevice,
            let outputDeviceSampleRate = await outputDeviceSampleRate
        else {
            return
        }

        guard await AudioDefaults.shared.isSupported(sampleRate: outputDeviceSampleRate) else {
            let errorEvent: Event = .error(
                NSError(
                    description:
                        "\(selectedOutputDevice.name) is set to an incompatible sample rate of \(outputDeviceSampleRate)"
                )
            )

            await send(event: errorEvent)
            return
        }

        let outputDeviceChanged = selectedOutputDevice.uid != deviceSettings.outputUID
        let inputDeviceChanged = await selectedInputDevice?.uid != deviceSettings.inputUID
        let sampleRateChanged = await outputDeviceSampleRate != systemSampleRate

        var options = Set<ConfigurationOption>()

        if outputDeviceChanged {
            options.insert(.outputDeviceChanged)
        }

        if inputDeviceChanged {
            options.insert(.inputDeviceChanged)
        }

        if sampleRateChanged {
            do {
                try await update(systemSampleRate: outputDeviceSampleRate)
                options.insert(.sampleRateChanged)

            } catch {
                Log.error(error)
            }
        }

        await send(event: .configurationChanged(options))
    }
}
