import AVFoundation
import Foundation
import SPFKUtils

extension AudioUnitCacheManager {
    internal func send(event: AudioUnitCacheEvent) {
        eventHandler?(event)
    }

    public func addObservers() {
        guard !isObserving else { return }

        Log.debug("adding observors...")

        // Sign up for a notification when the list of available components changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(componentRegistrationObserver),
            name: .ComponentRegistrationsChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(componentInstanceObserver),
            name: .ComponentInstanceInvalidation,
            object: nil
        )

        isObserving = true
    }

    func removeObservers() {
        guard isObserving else { return }

        NotificationCenter.default.removeObserver(componentRegistrationObserver)
        NotificationCenter.default.removeObserver(componentInstanceObserver)
        isObserving = false
    }

    @objc private func componentRegistrationObserver(notification: Foundation.Notification) {
        guard !isScanning else {
            Log.debug("*AU Don't send notification while scanning, notification", notification)
            return
        }

        guard componentCollection != nil else {
            Log.debug("*AU Don't send notification while componentCollection is nil, notification", notification)
            return
        }

        triggerComponentRegistrationEvent()
    }

    private func triggerComponentRegistrationEvent() {
        Log.debug("*AU Triggering: componentRegistrationsChanged event *")

        guard sendNotifications else {
            Log.error("notifications are disabled")
            return
        }

        // delay the event, it comes in fairly early before some installations are complete
        notificationTimer?.invalidate()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.send(event: .componentRegistrationsChanged)
        }
    }

    @objc private func componentInstanceObserver(notification: Notification) {
        guard let crashedAU = notification.object as? AUAudioUnit else {
            return
        }

        Log.error("* Audio Unit Crashed: \(crashedAU.debugDescription)")

        Task { @MainActor in
            self.send(event: .componentInvalidated(crashedAU))
        }
    }
}
