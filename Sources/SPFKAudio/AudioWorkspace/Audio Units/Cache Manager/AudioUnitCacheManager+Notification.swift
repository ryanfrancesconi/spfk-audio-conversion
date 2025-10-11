import AudioToolbox
import AVFoundation

extension Notification.Name {
    /// Notification generated when the set of available AudioComponents changes.
    public static let ComponentRegistrationsChanged = Notification.Name(
        rawValue: kAudioComponentRegistrationsChangedNotification as String
    )

    /**
     This notification can happen for several reasons, for instance the connection being
     invalidated or the process abnormally ending. There can be multiple notifications for
     the same event (i.e. a terminated process will also invalidate the connection).
     */
    public static let ComponentInstanceInvalidation = Notification.Name(
        rawValue: kAudioComponentInstanceInvalidationNotification as String
    )

    public static let effectsCacheUpdated = Notification.Name(
        rawValue: "com.spongefork.effectsCacheUpdated"
    )
}
