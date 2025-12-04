// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AEXML
import AppKit
import AVFoundation
import SPFKBase
import SwiftExtensions

public actor AudioUnitCacheManager {
    public weak var delegate: AudioUnitCacheManagerDelegate?
    public func update(delegate: AudioUnitCacheManagerDelegate?) {
        self.delegate = delegate
    }

    /// Where it writes its xml cache file. Can be set to an alternate directory for testing.
    public var cachesDirectory: URL?
    public func update(cachesDirectory: URL) {
        self.cachesDirectory = cachesDirectory
    }

    var cacheURL: URL?
    public func update(cacheURL: URL?) {
        self.cacheURL = cacheURL ?? defaultCacheURL()
    }

    private func defaultCacheURL() -> URL? {
        guard let folder = cachesDirectory else {
            return nil
        }

        let filename = "AudioUnitCache.xml"

        // the caches folder might not yet exist
        if !folder.exists {
            do {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                Log.error("Unable to create folder at \(folder.path)")
                return nil
            }
        }

        return folder.appendingPathComponent(filename)
    }

    var cachedComponentCount: Int?

    /// All results including effects that are incompatible
    public var componentCollection: ComponentCollection?

    public func update(componentCollectionResult result: ComponentValidationResult) {
        componentCollection?.update(result: result)
    }

    public func update(audioComponentDescription: AudioComponentDescription, isEnabled: Bool) {
        componentCollection?.update(audioComponentDescription: audioComponentDescription, isEnabled: isEnabled)
    }

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

    public init(cachesDirectory: URL? = nil, delegate: AudioUnitCacheManagerDelegate? = nil) {
        self.cachesDirectory = cachesDirectory
        self.delegate = delegate
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
            try await loadCache()
        }

        let result = await loadTask.result
        let systemComponentsResponse: SystemComponentsResponse

        switch result {
        case let .success(value):
            systemComponentsResponse = value
        case let .failure(error):
            throw error
        }

        let componentCollection = ComponentCollection(results: systemComponentsResponse.results)
        self.componentCollection = componentCollection

        Log.debug("*AU \(systemComponentsResponse.results.count) Effects are available now.")

        await send(event: .cacheLoaded(systemComponentsResponse))

        cacheObservation.start()

        return componentCollection
    }

    func send(event: AudioUnitCacheEvent) async {
        await delegate?.handleAudioUnitCacheManager(event: event)
    }
}

public protocol AudioUnitCacheManagerDelegate: AnyObject, Sendable {
    func handleAudioUnitCacheManager(event: AudioUnitCacheEvent) async
}
