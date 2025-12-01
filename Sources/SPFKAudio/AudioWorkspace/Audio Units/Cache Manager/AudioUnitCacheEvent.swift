import AVFoundation
import Foundation

public enum AudioUnitCacheEvent: Sendable {
    case cachingStarted
    case cacheUpdated
    case cacheLoaded(SystemComponentsResponse)

    /// Name of AU being currently validated
    case validating(name: String, index: Int, count: Int)
}
