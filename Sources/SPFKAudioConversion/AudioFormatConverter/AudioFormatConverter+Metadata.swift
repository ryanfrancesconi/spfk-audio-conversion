// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata

extension AudioFormatConverter {
    /// Copies metadata from the source file to the converted output file based on the
    /// ``AudioFormatConverterSource/metadataCopyScheme``.
    ///
    /// Each metadata type is copied independently with best-effort error handling — a failure
    /// in one step (e.g. unsupported marker format) does not prevent other metadata from being copied.
    func copyMetadata() async {
        let scheme = source.metadataCopyScheme

        guard scheme != .ignore else { return }

        // Finder tags are an extended attribute, so they are copied whatever the container.
        defer {
            if scheme.includesFinderTags {
                copyFinderTags()
            }
        }

        let outputType = AudioFileType(pathExtension: source.output.pathExtension)

        // Skip formats with no metadata support (e.g. CAF)
        guard let outputType, AudioFileType.metadataTypes.contains(outputType) else { return }

        let inputType = AudioFileType(pathExtension: source.input.pathExtension)

        if scheme.includesText {
            copyTags()
            copyBEXT(inputType: inputType, outputType: outputType)
            copyIXML(inputType: inputType, outputType: outputType)
        }

        if scheme.includesMarkers {
            await copyMarkers(outputType: outputType)
        }

        if scheme.includesImage {
            copyImage()
        }
    }

    // MARK: - Text Tags

    /// Copies all text tags (ID3, Vorbis, INFO, etc.) via TagLib's PropertyMap.
    private func copyTags() {
        do {
            try TagProperties.copyTags(from: source.input, to: source.output)
        } catch {
            Log.error("Failed to copy tags from \(source.input.lastPathComponent):", error)
            recordMetadataFailure(.tags, error)
        }
    }

    // MARK: - BEXT (WAV or FLAC)

    private func copyBEXT(inputType: AudioFileType?, outputType: AudioFileType) {
        guard let inputType, [AudioFileType.wav, .flac].contains(inputType),
              [AudioFileType.wav, .flac].contains(outputType)
        else { return }

        guard let bext = ProductionChunks.readBEXT(from: source.input, fileType: inputType) else { return }

        do {
            try ProductionChunks.writeBEXT(bext, to: source.output, fileType: outputType)
        } catch {
            Log.error("Failed to copy BEXT to \(source.output.lastPathComponent):", error)
            recordMetadataFailure(.bext, error)
        }
    }

    // MARK: - iXML (WAV or FLAC)

    private func copyIXML(inputType: AudioFileType?, outputType: AudioFileType) {
        guard let inputType, [AudioFileType.wav, .flac].contains(inputType),
              [AudioFileType.wav, .flac].contains(outputType)
        else { return }

        guard let ixml = ProductionChunks.readIXML(from: source.input, fileType: inputType) else { return }

        do {
            try ProductionChunks.writeIXML(ixml, to: source.output, fileType: outputType)
        } catch {
            Log.error("Failed to copy iXML to \(source.output.lastPathComponent):", error)
            recordMetadataFailure(.ixml, error)
        }
    }

    // MARK: - Markers

    private func copyMarkers(outputType: AudioFileType) async {
        let collection: AudioMarkerDescriptionCollection

        do {
            collection = try await AudioMarkerDescriptionCollection(url: source.input)
        } catch {
            // Source has no markers or format doesn't support reading them
            return
        }

        guard collection.count > 0 else { return }

        if !AudioFormatConverter.writeMarkers(collection.markerDescriptions, to: source.output, outputType: outputType) {
            recordMetadataFailure(.markers, "\(collection.count) markers could not be written")
        }
    }

    /// `EmbeddedMarkers.write`, which leaves the file's tags alone, reporting a failure as `false`.
    ///
    /// - Returns: `false` when the write failed. A format with no marker support returns `true`:
    ///   there was nothing it could have written.
    @discardableResult
    public static func writeMarkers(
        _ descriptions: [AudioMarkerDescription],
        to url: URL,
        outputType: AudioFileType
    ) -> Bool {
        do {
            try EmbeddedMarkers.write(descriptions, to: url, fileType: outputType)
        } catch MetadataError.unsupportedFormat {
            Log.debug("Marker writing not supported for \(outputType.rawValue) — skipping")
        } catch {
            Log.error("Failed to write markers to \(url.lastPathComponent):", error)
            return false
        }

        return true
    }

    /// Removes every marker from `url`, dispatching on `outputType`.
    ///
    /// The counterpart to ``writeMarkers(_:to:outputType:)`` for a set that came out empty.
    /// Writing an empty set is not the same operation: it leaves whatever is already in the file,
    /// and a trim render can arrive carrying the source's markers at their pre-trim times.
    ///
    /// Returns whether anything was removed — `false` also covers a file that had no markers, so
    /// it is a poor error signal and is not treated as one.
    @discardableResult
    public static func removeMarkers(from url: URL, outputType: AudioFileType) -> Bool {
        do {
            return try EmbeddedMarkers.removeAll(from: url, fileType: outputType)
        } catch {
            Log.debug("Marker removal not supported for \(outputType.rawValue) — skipping")
            return false
        }
    }

    // MARK: - Finder Tags

    private func copyFinderTags() {
        do {
            try source.input.copyFinderTags(to: source.output)
        } catch {
            Log.error("Failed to copy Finder tags to \(source.output.lastPathComponent):", error)
            recordMetadataFailure(.finderTags, error)
        }
    }

    // MARK: - Image

    private func copyImage() {
        // No image, or one that can't be read, leaves nothing to carry.
        guard let artwork = try? EmbeddedArtwork.read(from: source.input) else { return }

        do {
            try artwork.write(to: source.output)
        } catch {
            Log.error("Failed to write image to \(source.output.lastPathComponent)")
            recordMetadataFailure(.image, "The image could not be written")
        }
    }

    // MARK: - Failures

    func recordMetadataFailure(_ category: AudioFormatConverterMetadataFailure.Category, _ error: Error) {
        recordMetadataFailure(category, error.localizedDescription)
    }

    func recordMetadataFailure(_ category: AudioFormatConverterMetadataFailure.Category, _ reason: String) {
        source.metadataFailures.append(AudioFormatConverterMetadataFailure(category: category, reason: reason))
    }
}
