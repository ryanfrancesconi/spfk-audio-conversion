import Foundation
import SPFKAudioHardware
import SPFKUtils

extension AudioDeviceManager {
    @MainActor func send(event: Event) async {
        Log.debug("🔊 \(event)")

        await delegate?.audioDeviceManager(event: event)
    }

    func removeHardwareObservers() {
        hardwareObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }

        hardwareObservers.removeAll()
    }

    func addHardwareObservers() {
        removeHardwareObservers()

        hardwareObservers = [
            NotificationCenter.default.addObserver(
                forName: .deviceListChanged,
                object: nil,
                queue: .main
            ) { [weak self] in self?.parse(notification: $0) },

            NotificationCenter.default.addObserver(
                forName: .defaultInputDeviceChanged,
                object: nil,
                queue: .main
            ) { [weak self] in self?.parse(notification: $0) },

            NotificationCenter.default.addObserver(
                forName: .defaultOutputDeviceChanged,
                object: nil,
                queue: .main
            ) { [weak self] in self?.parse(notification: $0) },

            NotificationCenter.default.addObserver(
                forName: .deviceNominalSampleRateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] in self?.parse(notification: $0) },

            NotificationCenter.default.addObserver(
                forName: .deviceProcessorOverload,
                object: nil,
                queue: .main
            ) { [weak self] in self?.parse(notification: $0) },
        ]
    }

    @objc private func parse(notification: Notification) {
        Task {
            if let hardwareNotification = notification.object as? AudioHardwareNotification {
                await parse(hardwareNotification: hardwareNotification)

            } else if let deviceNotification = notification.object as? AudioDeviceNotification {
                await parse(deviceNotification: deviceNotification)
            }
        }
    }

    private func parse(hardwareNotification: AudioHardwareNotification) async {
        switch hardwareNotification {
        case .defaultSystemOutputDeviceChanged:
            break

        case .defaultInputDeviceChanged:
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

        case .defaultOutputDeviceChanged:
            guard await self.allowInput else {
                Log.debug("Can ignore this defaultOutputDeviceChanged")
                return
            }

            guard let defaultOutputDevice = await self.defaultOutputDevice else {
                assertionFailure()
                return
            }

            guard defaultOutputDevice.uid != self.deviceSettings.outputUID else {
                Log.debug("Same device is already selected", defaultOutputDevice)
                return
            }

            await self.send(event: .outputDeviceChanged(device: defaultOutputDevice))

        case let .deviceListChanged(event: event):
            let added = event.addedDevices.filter { !Self.isEngineDefaultAggregate(device: $0) }
            let removed = event.removedDevices.filter { !Self.isEngineDefaultAggregate(device: $0) }

            guard added.isNotEmpty || removed.isNotEmpty else { return }

            let filteredEvent = DeviceStatusEvent(
                addedDevices: added,
                removedDevices: removed
            )

            await self.send(event: .deviceListChanged(event: filteredEvent))
        }
    }

    private func parse(deviceNotification: AudioDeviceNotification) async {
        guard let notificationDevice = await deviceNotification.getAudioDevice() else { return }

        let devices = [
            await self.selectedInputDevice,
            await self.selectedOutputDevice,
        ]

        guard devices.contains(notificationDevice) else { return }

        switch deviceNotification {
        case .deviceAvailableNominalSampleRatesDidChange:
            guard let sampleRate = notificationDevice.nominalSampleRate else { return }
            await self.send(event: .sampleRateChanged(sampleRate))

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
