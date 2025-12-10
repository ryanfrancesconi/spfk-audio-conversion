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

    @MainActor
    func addObservers() {
        removeObservers()

        hardwareObservers = [
            NotificationCenter.default.addObserver(
                forName: .deviceListChanged, object: nil, queue: .main,
                using: { [weak self] notification in
                    self?.parse(notification: SendableNotification(notification))
                }
            ),
            NotificationCenter.default.addObserver(
                forName: .defaultInputDeviceChanged, object: nil, queue: .main,
                using: { [weak self] notification in
                    self?.parse(notification: SendableNotification(notification))
                }
            ),
            NotificationCenter.default.addObserver(
                forName: .defaultOutputDeviceChanged, object: nil, queue: .main,
                using: { [weak self] notification in
                    self?.parse(notification: SendableNotification(notification))
                }
            ),
            NotificationCenter.default.addObserver(
                forName: .deviceNominalSampleRateDidChange, object: nil, queue: .main,
                using: { [weak self] notification in
                    self?.parse(notification: SendableNotification(notification))
                }
            ),
            NotificationCenter.default.addObserver(
                forName: .deviceProcessorOverload, object: nil, queue: .main,
                using: { [weak self] notification in
                    self?.parse(notification: SendableNotification(notification))
                }
            ),
        ]
    }

    @MainActor
    func removeObservers() {
        for hardwareObserver in hardwareObservers {
            NotificationCenter.default.removeObserver(hardwareObserver)
        }

        hardwareObservers.removeAll()
    }

    private func parse(notification sendable: SendableNotification) {
        guard let notification = sendable.notification else { return }

        notificationTask?.cancel()
        notificationTask = Task<Void, Error> {
            // Extract a Sendable payload first to avoid capturing Notification/self in a concurrent context.
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
            guard await allowInput else {
                Log.debug("Can ignore this event")
                return
            }

            guard let defaultInputDevice = await hardware.defaultInputDevice else { return }

            let currentInputUID = await deviceSettings.inputUID

            guard defaultInputDevice.uid != currentInputUID else {
                Log.debug("Same device is already selected", defaultInputDevice)
                return
            }

            await send(event: .inputDeviceChanged(device: defaultInputDevice))

        case .defaultOutputDeviceChanged:
            guard await allowInput else {
                Log.debug("Can ignore this defaultOutputDeviceChanged")
                return
            }

            guard let defaultOutputDevice = await hardware.defaultOutputDevice else {
                assertionFailure()
                return
            }

            let currentOutputUID = await deviceSettings.outputUID

            guard defaultOutputDevice.uid != currentOutputUID else {
                Log.debug("Same device is already selected", defaultOutputDevice)
                return
            }

            await send(event: .outputDeviceChanged(device: defaultOutputDevice))

        case .deviceListChanged(objectID: _, let event):
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

        let devices = await [
            selectedInputDevice,
            selectedOutputDevice,
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

        let currentInputUID = await deviceSettings.inputUID
        let currentOutputUID = await deviceSettings.outputUID

        let inputDeviceChanged = await selectedInputDevice?.uid != currentInputUID
        let outputDeviceChanged = selectedOutputDevice.uid != currentOutputUID
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
