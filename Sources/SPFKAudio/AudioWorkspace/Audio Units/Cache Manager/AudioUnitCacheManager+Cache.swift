// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AEXML
import AppKit
import AVFoundation
import SPFKBase
import SwiftExtensions

extension AudioUnitCacheManager {
    public var validationIsNeeded: Bool {
        AudioUnitCacheManager.compatibleComponents.count != cachedComponentCount
    }

    func cacheDocument() throws -> AEXMLDocument {
        guard let cacheURL else {
            throw NSError(description: "*AU nil cache URL")
        }

        guard cacheURL.exists else {
            throw NSError(description: "*AU AudioUnitCache.xml wasn't found")
        }

        guard let doc = try? AEXMLDocument(fromURL: cacheURL) else {
            throw NSError(description: "*AU Failed to parse cache file. Document is invalid.")
        }

        Log.debug("*AU Parsed", cacheURL.path)

        return doc
    }

    // MARK: - loading effects

    /// Load AudioComponentDescription list from xml cache file
    /// - Parameter completionHandler: callback with an array of `AVAudioUnitComponent`
    func loadCache() async throws -> SystemComponentsResponse {
        cachedComponentCount = nil

        var response = SystemComponentsResponse()

        let doc = try cacheDocument()
        response = try await parse(cache: doc)

        return response
    }

    func parse(cache doc: AEXMLDocument) async throws -> SystemComponentsResponse {
        guard let collection = doc.root["au"].all,
              collection.isNotEmpty
        else {
            throw NSError(description: "*AU No entries in cache file")
        }

        // the last saved value
        cachedComponentCount = doc.root.attributes["cachedComponentCount"]?.int

        // proceed to parse what is in the cache regardless
        // and convert to components
        var out = [ComponentValidationResult]()

        out = collection.compactMap {
            parse(cacheItem: $0)
        }

        out = out.sorted(by: { lhs, rhs in
            lhs.manufacturerName < rhs.manufacturerName
        })

        return SystemComponentsResponse(results: out)
    }

    private func parse(cacheItem item: AEXMLElement) -> ComponentValidationResult? {
        guard let componentType = item.attributes["componentType"]?.uInt32,
              let componentSubType = item.attributes["componentSubType"]?.uInt32,
              let componentManufacturer = item.attributes["componentManufacturer"]?.uInt32
        else {
            Log.error("Failed to create required data from \(item.xmlCompact)")

            return nil
        }

        let componentFlags = item.attributes["componentFlags"]?.uInt32 ?? 0
        let componentFlagsMask = item.attributes["componentFlagsMask"]?.uInt32 ?? 0

        var isEnabled = true

        if let value = item.attributes["isEnabled"]?.boolValue {
            isEnabled = value
        }

        let audioComponentDescription = AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: componentFlags,
            componentFlagsMask: componentFlagsMask
        )

        var component: AVAudioUnitComponent?

        if isEnabled, let avComponent = AVAudioUnitComponentManager.shared()
            .components(matching: audioComponentDescription)
            .first
        {
            component = avComponent
        }

        var validationResult: AudioComponentValidationResult?

        if let desc = item.attributes["validation"],
           let value = AudioComponentValidationResult(description: desc)
        {
            validationResult = value
        }

        let validation = AudioUnitValidator.ValidationResult(result: validationResult ?? .passed)

        let result: ComponentValidationResult = if let component {
            ComponentValidationResult(
                audioComponentDescription: audioComponentDescription,
                component: component,
                validation: validation,
                isEnabled: isEnabled
            )
        } else {
            ComponentValidationResult(audioComponentDescription: audioComponentDescription, validation: validation, isEnabled: isEnabled, name: item.attributes["name"] ?? "", typeName: item.attributes["typeName"] ?? "", manufacturerName: item.attributes["manufacturerName"] ?? "", versionString: item.attributes["version"] ?? "", icon: nil)
        }

        return result
    }

    /// Called to refresh the internal Audio Unit cache by collecting system AUs
    /// - Parameter completionHandler: handler
    public func createCache() async throws {
        await send(event: .cachingStarted)

        // preserve previous enabled values...

        let previousCollection = componentCollection

        removeCache()

        let results = try await validate()

        componentCollection = ComponentCollection(results: results)

        // reapply isEnabled or if missing true
        if let value = previousCollection {
            componentCollection?.update(from: value)
        }

        try await writeCache()

        await send(event: .cacheUpdated)
    }

    /// Write current component collection to disk
    public func writeCache() async throws {
        guard let cacheURL else {
            Log.error("*AU Failed to create cache URL")
            return
        }

        guard let effects: [ComponentValidationResult] = componentCollection?.validationResults else {
            Log.error("*AU componentCollection is nil")
            return
        }

        removeCache()

        let componentCountOnDisk = AudioUnitCacheManager.compatibleComponents.count // Self.audioComponentCount

        let effectsAttributes = ["cachedComponentCount": String(componentCountOnDisk)]
        let root = AEXMLElement(name: "effects", value: nil, attributes: effectsAttributes)

        for au in effects {
            let acd = au.audioComponentDescription

            let attributes = [
                "name": au.name,
                "manufacturerName": au.manufacturerName,
                "typeName": au.typeName,
                "version": au.versionString,
                "componentType": String(describing: acd.componentType),
                "componentSubType": String(describing: acd.componentSubType),
                "componentManufacturer": String(describing: acd.componentManufacturer),
                "componentFlags": String(describing: acd.componentFlags),
                "componentFlagsMask": String(describing: acd.componentFlagsMask),
                "validation": au.validation.result.description,
                "isEnabled": au.isEnabled.string,
            ]

            root.addChild(name: "au", value: nil, attributes: attributes)
        }

        let doc = AEXMLDocument(root: root, options: AEXMLOptions())

        // Log.debug(doc.xml)

        Log.debug("*AU Writing cache to", cacheURL)

        let string = doc.xml.removing(characters: .null)
        try string.write(to: cacheURL,
                         atomically: false,
                         encoding: .utf8)

        Log.debug("*AU Wrote cache to", cacheURL)
    }

    func removeCache() {
        guard let cacheURL, cacheURL.exists else { return }

        do {
            try cacheURL.delete()
            Log.debug("*AU Deleted", cacheURL)

        } catch {
            Log.error("*AU Failed to delete cache file...", error.localizedDescription)
        }
    }
}
