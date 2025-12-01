// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AEXML
import AppKit
import AVFoundation
import SPFKBase
import SwiftExtensions

public actor AudioUnitCacheManager {
    public var eventHandler: ((AudioUnitCacheEvent) -> Void)?
    public func update(eventHandler: ((AudioUnitCacheEvent) -> Void)?) {
        self.eventHandler = eventHandler
    }

    /// Where it writes its xml cache file. Can be set to an alternate directory for testing.
    public var cachesDirectory: URL?
    public func update(cachesDirectory: URL) {
        self.cachesDirectory = cachesDirectory
    }

    var cachedComponentCount: Int?

    /// All results including effects that are incompatible
    public var componentCollection: ComponentCollection?

    /// Task to abort scanning
    var scanTask: Task<[ComponentValidationResult], Error>?

    // MARK: - Observation

    var isScanning: Bool { scanTask != nil }

    // HACK: some special cases to allow through the filter
    var allowedComponentDescriptions = [
        AVAudioUnitVarispeed().audioComponentDescription,
    ]

    public var debugDescription: String {
        let names = AudioUnitCacheManager.compatibleComponents.map(\.name).sorted()

        var out = "\(names.count) total Audio Unit\(names.pluralString) found\n\n"
        out += names.joined(separator: ", ")
        out += "\n\n"

        if let path = cacheURL?.path {
            out += "Cached at: \(path)"
        }

        return out
    }

    var cacheObservation: AudioUnitCacheObservation = .init()

    public init(cachesDirectory: URL? = nil, eventHandler: ((AudioUnitCacheEvent) -> Void)? = nil) {
        self.cachesDirectory = cachesDirectory
    }

    public func dispose() {
        cacheObservation.stop()
        componentCollection = nil
    }

    deinit {
        Log.debug("* { AudioUnitCacheManager }")
    }

    public func cancelScan() {
        guard isScanning else {
            Log.error("isScanning is false")
            return
        }

        scanTask?.cancel()
    }

    /// load effects cache document
    public func load() async throws -> ComponentCollection {
        // already loaded
        if let componentCollection {
            return componentCollection
        }

        // request plugins
        Log.debug("*AU Loading cached Audio Units...")

        let loadTask = Task<SystemComponentsResponse, Error> {
            await loadCache()
        }

        let systemComponentsResponse = try await loadTask.value

        let componentCollection = ComponentCollection(results: systemComponentsResponse.results)
        self.componentCollection = componentCollection

        Log.debug("*AU \(systemComponentsResponse.results.count) Effects are available now.")

        await send(event: .cacheLoaded(systemComponentsResponse))

        cacheObservation.start()

        return componentCollection
    }

    func send(event: AudioUnitCacheEvent) async {
        eventHandler?(event)
    }
}
