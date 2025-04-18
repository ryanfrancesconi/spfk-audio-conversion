import AVFoundation


public extension Notification.Name {
    /// Notification generated when the set of available AudioComponents changes.
    static let ComponentRegistrationsChanged = Notification.Name(
        rawValue: kAudioComponentRegistrationsChangedNotification as String
    )

    /**
     This notification can happen for several reasons, for instance the connection being
     invalidated or the process abnormally ending. There can be multiple notifications for
     the same event (i.e. a terminated process will also invalidate the connection).
     */
    static let ComponentInstanceInvalidation = Notification.Name(
        rawValue: kAudioComponentInstanceInvalidationNotification as String
    )

    static let effectsCacheUpdated = Notification.Name(
        rawValue: "com.audiodesigndesk.ADD.effectsCacheUpdated"
    )
}

extension AudioUnitCacheManager {
    public typealias ComponentListCallback = ([AVAudioUnitComponent]?) -> Void

    public enum Event {
        case cachingStarted
        
        case cacheUpdated
        
        case cacheLoaded(SystemComponentsResponse)

        /// Name of AU being currently validated
        case validating(name: String, index: Int, count: Int)

        case componentRegistrationsChanged
        
        case componentInvalidated(AUAudioUnit)
    }

    public struct SystemComponentsResponse {
        public var results = [ComponentValidationResult]()

        public init(results: [ComponentValidationResult] = []) {
            self.results = results
        }
    }
}
