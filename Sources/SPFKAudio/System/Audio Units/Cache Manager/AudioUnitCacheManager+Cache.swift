import AEXML
import AppKit
import AVFoundation
import OTCore
import SPFKUtils

extension AudioUnitCacheManager {
    public var validationIsNeeded: Bool {
        guard let cachedComponentCount else { return true }

        // ask the system for the amount of components
        let audioComponentCount = AudioUnitCacheManager.compatibleComponents.count

        let needsValidation = audioComponentCount != cachedComponentCount

        if needsValidation {
            Log.error("*AU Need to regenerate cache file as validation count doesn't match",
                      "componentCountOnDisk:", audioComponentCount,
                      "vs cachedComponentCount:", cachedComponentCount)
        } else {
            Log.debug("*AU No validation is needed: componentCountOnDisk:", audioComponentCount,
                      "vs cachedComponentCount:", cachedComponentCount)
        }

        return needsValidation
    }

    var cacheURL: URL? {
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

    var cacheDocument: AEXMLDocument? {
        guard let cacheURL else {
            Log.error("*AU Invalid cache URL", cacheURL)
            return nil
        }

        guard cacheURL.exists else {
            Log.error("*AU AudioUnitCache.xml wasn't found")
            return nil
        }

        guard let doc = try? AEXMLDocument(fromURL: cacheURL) else {
            Log.error("*AU Failed to parse cache file. Document is invalid.")
            return nil
        }

        Log.debug("*AU Parsed", cacheURL.path)

        return doc
    }

    var cacheExists: Bool {
        cacheURL?.exists == true
    }

    // MARK: - loading effects

    /// Load AudioComponentDescription list from xml cache file
    /// - Parameter completionHandler: callback with an array of `AVAudioUnitComponent`
    func loadCache() async -> SystemComponentsResponse {
        cachedComponentCount = nil

        var response = SystemComponentsResponse()

        if let doc = cacheDocument {
            response = parse(cache: doc)
        }

        return response
    }

    func parse(cache doc: AEXMLDocument) -> SystemComponentsResponse {
        guard let aus = doc.root["au"].all,
              aus.isNotEmpty else {
            Log.error("*AU No entries in cache file")
            return SystemComponentsResponse()
        }

        // the last saved value
        cachedComponentCount = doc.root.attributes["cachedComponentCount"]?.int

        // proceed to parse what is in the cache regardless
        // and convert to components
        var out = [ComponentValidationResult]()

        out = aus.compactMap {
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
              let componentManufacturer = item.attributes["componentManufacturer"]?.uInt32 else {
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
            .first {
            component = avComponent
        }

        var validationResult: AudioComponentValidationResult?

        if let desc = item.attributes["validation"],
           let value = AudioComponentValidationResult(description: desc) {
            validationResult = value
        }

        var result = ComponentValidationResult(
            audioComponentDescription: audioComponentDescription,
            component: component,
            validation: AudioUnitValidator.ValidationResult(result: validationResult ?? .passed),
            isEnabled: isEnabled
        )

        if component == nil {
            result.name = item.attributes["name"] ?? ""
            result.versionString = item.attributes["version"] ?? ""
            result.typeName = item.attributes["typeName"] ?? ""
            result.manufacturerName = item.attributes["manufacturerName"] ?? ""
        }

        return result
    }

    /// Called to refresh the internal Audio Unit cache by collecting system AUs
    /// - Parameter completionHandler: handler
    public func createCache() async {
        sendEvent(.cachingStarted)

        // preserve previous enabled values...

        let previousCollection = componentCollection

        removeCache()

        let results = (try? await validate()) ?? []

        componentCollection = ComponentCollection(results: results)

        // reapply isEnabled or if missing true
        if let value = previousCollection {
            componentCollection?.update(from: value)
        }

        await writeCache()

        sendEvent(.cacheUpdated)
    }

    /// Write current component collection to disk
    public func writeCache() async {
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

        do {
            let string = doc.xml.removing(characters: .null)
            try string.write(to: cacheURL,
                             atomically: false,
                             encoding: .utf8)

            Log.debug("*AU Wrote cache to", cacheURL)

        } catch let error as NSError {
            Log.error("*AU There was an error saving the audio unit cache.", error.localizedDescription)
            return
        }
    }

    func removeCache() {
        guard cacheExists else { return }
        guard let cacheURL = cacheURL else { return }

        do {
            try cacheURL.delete()
            Log.debug("*AU Deleted", cacheURL)

        } catch {
            Log.error("*AU Failed to delete cache file...", error.localizedDescription)
        }
    }
}
