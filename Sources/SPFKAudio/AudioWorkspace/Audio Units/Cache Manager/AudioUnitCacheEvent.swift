import AVFoundation
import Foundation

public enum AudioUnitCacheEvent {
    case cachingStarted

    case cacheUpdated

    case cacheLoaded(SystemComponentsResponse)

    /// Name of AU being currently validated
    case validating(name: String, index: Int, count: Int)

    case componentRegistrationsChanged

    case componentInvalidated(AUAudioUnit)
}
