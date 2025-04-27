
import AEXML
import AppKit
import AVFoundation
import OTCore
import SPFKUtils

public class AudioUnitCacheManager {
    public var eventHandler: ((Event) -> Void)?

    /// Where it writes its xml cache file. Can be set to an alternate directory for testing.
    public var cachesDirectory: URL?

    var cachedComponentCount: Int?

    /// All results including effects that are incompatible
    public var componentCollection: ComponentCollection?

    /// Task to abort scanning
    var scanTask: Task<[ComponentValidationResult], Error>?

    // MARK: - Observation

    var isScanning: Bool { scanTask != nil }

    public var notificationTimer: Timer?

    public var sendNotifications: Bool = false

    var isObserving = false

    // HACK: some special cases to allow through the filter
    var allowedComponentDescriptions = [AVAudioUnitVarispeed().audioComponentDescription]

    public var debugDescription: String {
        let names = AudioUnitCacheManager.compatibleComponents.map { $0.name }.sorted()

        var out = "\(names.count) total Audio Unit\(names.pluralString) found\n\n"
        out += names.joined(separator: ", ")
        out += "\n\n"

        if let path = cacheURL?.path {
            out += "Cached at: \(path)"
        }

        return out
    }

    public init(cachesDirectory: URL? = nil) {
        self.cachesDirectory = cachesDirectory
    }

    deinit {
        Log.debug("* { AudioUnitCacheManager }")
        removeObservers()
        componentCollection = nil
    }

    public func cancelScan() {
        guard isScanning else {
            Log.error("isScanning is false")
            return
        }

        scanTask?.cancel()
    }

    /// load effects cache document
    public func load() async {
        guard componentCollection == nil else {
            // already loaded
            return
        }

        // request plugins
        Log.debug("*AU Loading cached Audio Units...")

        let systemComponentsResponse = await loadCache()

        componentCollection = ComponentCollection(results: systemComponentsResponse.results)

        Log.debug("*AU \(systemComponentsResponse.results.count) Effects are available now.")

        sendEvent(
            .cacheLoaded(systemComponentsResponse)
        )
    }
}
