// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata
import SPFKMetadataBase
import SPFKMetadataC

/// Pastes a filtered subset of metadata from one audio file to another.
///
/// All operations are best-effort — a failure in one section does not prevent
/// the remaining sections from being processed.
public enum MetadataPaster {
    /// Pastes metadata from `source` to `destination` according to `options`.
    ///
    /// - Parameters:
    ///   - options: Which metadata types and fields to transfer.
    ///   - source: The file to read metadata from.
    ///   - destination: The file to write metadata to.
    public static func paste(
        _ options: PasteAttributesOptions,
        from source: URL,
        to destination: URL
    ) async {
        if options.tags {
            pasteTags(options, from: source, to: destination)
        }

        if options.bext {
            pasteBEXT(options, from: source, to: destination)
        }

        if options.ixml {
            pasteIXML(options, from: source, to: destination)
        }

        if options.markers {
            await pasteMarkers(from: source, to: destination)
        }

        if options.image {
            pasteImage(from: source, to: destination)
        }

        if options.finderTags {
            pasteFinderTags(from: source, to: destination)
        }
    }
}

// MARK: - Tags

extension MetadataPaster {
    private static func pasteTags(_ options: PasteAttributesOptions, from source: URL, to destination: URL) {
        do {
            if options.excludedTagKeys.isEmpty {
                // Fast path: bulk TagLib copy replaces all destination tags
                try TagProperties.copyTags(from: source, to: destination)
            } else {
                try pasteFilteredTags(options.excludedTagKeys, from: source, to: destination)
            }
        } catch {
            Log.error("Failed to paste tags to \(destination.lastPathComponent):", error)
        }
    }

    private static func pasteFilteredTags(
        _ excluded: Set<String>,
        from source: URL,
        to destination: URL
    ) throws {
        let sourceTags = try TagProperties(url: source)
        var destTags = (try? TagProperties(url: destination)) ?? TagProperties()

        for (key, value) in sourceTags.tags where !excluded.contains(key.rawValue) {
            destTags.tags[key] = value
        }

        try destTags.save(to: destination)
    }
}

// MARK: - BEXT

extension MetadataPaster {
    private static func pasteBEXT(_ options: PasteAttributesOptions, from source: URL, to destination: URL) {
        let sourceType = AudioFileType(pathExtension: source.pathExtension)
        let destType = AudioFileType(pathExtension: destination.pathExtension)

        guard let sourceBEXT = readBEXT(from: source, type: sourceType) else { return }

        let destBEXT: BEXTDescription
        if options.excludedBEXTFields.isEmpty {
            destBEXT = sourceBEXT
        } else {
            var merged = readBEXT(from: destination, type: destType) ?? BEXTDescription()
            var dict = merged.dictionary
            for (key, value) in sourceBEXT.dictionary where !options.excludedBEXTFields.contains(key.displayName) {
                dict[key] = value
            }
            merged.dictionary = dict
            destBEXT = merged
        }

        do {
            try writeBEXT(destBEXT, to: destination, type: destType)
        } catch {
            Log.error("Failed to paste BEXT to \(destination.lastPathComponent):", error)
        }
    }

    static func readBEXT(from url: URL, type: AudioFileType?) -> BEXTDescription? {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load(), let info = file.bextDescriptionC else { return nil }
            return BEXTDescription(info: info)

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else { return nil }
            return file.bextDescription

        default:
            return nil
        }
    }

    static func writeBEXT(_ bext: BEXTDescription, to url: URL, type: AudioFileType?) throws {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for BEXT writing")
            }
            file.bextDescriptionC = bext.bextDescriptionC
            file.markersNeedsSave = false
            file.imageNeedsSave = false
            guard file.save() else {
                throw NSError(description: "Failed to write BEXT to \(url.lastPathComponent)")
            }

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for BEXT writing")
            }
            file.bextDescription = bext
            guard file.save() else {
                throw NSError(description: "Failed to write BEXT to \(url.lastPathComponent)")
            }

        default:
            break
        }
    }
}

// MARK: - iXML

extension MetadataPaster {
    private static func pasteIXML(_ options: PasteAttributesOptions, from source: URL, to destination: URL) {
        let sourceType = AudioFileType(pathExtension: source.pathExtension)
        let destType = AudioFileType(pathExtension: destination.pathExtension)

        guard let sourceXMLString = readIXML(from: source, type: sourceType),
              let sourceMetadata = try? IXMLMetadata(xml: sourceXMLString)
        else { return }

        let xmlString: String
        if options.excludedIXMLFields.isEmpty {
            xmlString = sourceXMLString
        } else {
            let destXMLString = readIXML(from: destination, type: destType)
            var destMetadata = (destXMLString.flatMap { try? IXMLMetadata(xml: $0) }) ?? IXMLMetadata()

            for descriptor in IXMLTagDescriptor.allDescriptors
                where !options.excludedIXMLFields.contains(descriptor.identifier)
            {
                destMetadata.setValue(sourceMetadata.value(for: descriptor), for: descriptor)
            }

            xmlString = destMetadata.xml
        }

        do {
            try writeIXML(xmlString, to: destination, type: destType)
        } catch {
            Log.error("Failed to paste iXML to \(destination.lastPathComponent):", error)
        }
    }

    static func readIXML(from url: URL, type: AudioFileType?) -> String? {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load() else { return nil }
            return file.iXML

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else { return nil }
            return file.iXML

        default:
            return nil
        }
    }

    static func writeIXML(_ xml: String, to url: URL, type: AudioFileType?) throws {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for iXML writing")
            }
            file.iXML = xml
            file.markersNeedsSave = false
            file.imageNeedsSave = false
            guard file.save() else {
                throw NSError(description: "Failed to write iXML to \(url.lastPathComponent)")
            }

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for iXML writing")
            }
            file.iXML = xml
            guard file.save() else {
                throw NSError(description: "Failed to write iXML to \(url.lastPathComponent)")
            }

        default:
            break
        }
    }
}

// MARK: - Markers

extension MetadataPaster {
    private static func pasteMarkers(from source: URL, to destination: URL) async {
        let collection: AudioMarkerDescriptionCollection
        do {
            collection = try await AudioMarkerDescriptionCollection(url: source)
        } catch {
            return
        }

        guard collection.count > 0 else { return }

        let outputType = AudioFileType(pathExtension: destination.pathExtension)
        guard let outputType else { return }

        AudioFormatConverter.writeMarkers(collection.markerDescriptions, to: destination, outputType: outputType)
    }
}

// MARK: - Image

extension MetadataPaster {
    private static func pasteImage(from source: URL, to destination: URL) {
        do {
            let pictureRef = try TagPictureRef.parsing(url: source)
            if !TagPicture.write(pictureRef, path: destination.path) {
                Log.error("Failed to paste image to \(destination.lastPathComponent)")
            }
        } catch {
            // Source has no embedded image
        }
    }
}

// MARK: - Finder Tags

extension MetadataPaster {
    private static func pasteFinderTags(from source: URL, to destination: URL) {
        do {
            try source.copyFinderTags(to: destination)
        } catch {
            Log.error("Failed to paste Finder tags to \(destination.lastPathComponent):", error)
        }
    }
}
