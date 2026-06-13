// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata
import SPFKMetadataC

extension AudioFormatConverter {
    /// Copies metadata from the source file to the converted output file based on the
    /// ``AudioFormatConverterSource/metadataCopyScheme``.
    ///
    /// Each metadata type is copied independently with best-effort error handling — a failure
    /// in one step (e.g. unsupported marker format) does not prevent other metadata from being copied.
    func copyMetadata() async {
        let scheme = source.metadataCopyScheme

        guard scheme != .ignore else { return }

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

        if scheme.includesFinderTags {
            copyFinderTags()
        }
    }

    // MARK: - Text Tags

    /// Copies all text tags (ID3, Vorbis, INFO, etc.) via TagLib's PropertyMap.
    private func copyTags() {
        do {
            try TagProperties.copyTags(from: source.input, to: source.output)
        } catch {
            Log.error("Failed to copy tags from \(source.input.lastPathComponent):", error)
        }
    }

    // MARK: - BEXT (WAV or FLAC)

    private func copyBEXT(inputType: AudioFileType?, outputType: AudioFileType) {
        guard let inputType, [AudioFileType.wav, .flac].contains(inputType),
              [AudioFileType.wav, .flac].contains(outputType)
        else { return }

        guard let bext = MetadataPaster.readBEXT(from: source.input, type: inputType) else { return }

        do {
            try MetadataPaster.writeBEXT(bext, to: source.output, type: outputType)
        } catch {
            Log.error("Failed to copy BEXT to \(source.output.lastPathComponent):", error)
        }
    }

    // MARK: - iXML (WAV or FLAC)

    private func copyIXML(inputType: AudioFileType?, outputType: AudioFileType) {
        guard let inputType, [AudioFileType.wav, .flac].contains(inputType),
              [AudioFileType.wav, .flac].contains(outputType)
        else { return }

        guard let ixml = MetadataPaster.readIXML(from: source.input, type: inputType) else { return }

        do {
            try MetadataPaster.writeIXML(ixml, to: source.output, type: outputType)
        } catch {
            Log.error("Failed to copy iXML to \(source.output.lastPathComponent):", error)
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

        AudioFormatConverter.writeMarkers(collection.markerDescriptions, to: source.output, outputType: outputType)
    }

    /// Writes an array of marker descriptions to the given URL using the format-appropriate
    /// marker writing utility. Called by `copyMarkers` and by `AudioEditRenderer` after
    /// adjusting marker times to account for trim operations.
    static func writeMarkers(
        _ descriptions: [AudioMarkerDescription],
        to url: URL,
        outputType: AudioFileType
    ) {
        switch outputType {
        case .wav, .w64, .aiff, .aifc:
            // RIFF cue points via AudioToolbox
            let audioMarkers = descriptions.enumerated().map { i, desc in
                AudioMarker(
                    name: desc.name ?? "Marker",
                    time: desc.startTime,
                    sampleRate: desc.sampleRate ?? 0,
                    markerID: Int32(i)
                )
            }

            if !AudioMarkerUtil.write(audioMarkers, to: url) {
                Log.error("Failed to write markers to \(url.lastPathComponent)")
            }

        case .mp3:
            // ID3 CHAP frames via TagLib
            let chapters = descriptions.map { desc in
                ChapterMarker(
                    name: desc.name ?? "Chapter",
                    startTime: desc.startTime,
                    endTime: desc.endTime ?? desc.startTime
                )
            }

            if !MPEGChapterUtil.write(chapters, to: url.path) {
                Log.error("Failed to write chapters to \(url.lastPathComponent)")
            }

        case .flac, .ogg, .opus:
            // Vorbis comment chapters via TagLib XiphComment
            let chapters = descriptions.map { desc in
                ChapterMarker(
                    name: desc.name ?? "Chapter",
                    startTime: desc.startTime,
                    endTime: desc.endTime ?? desc.startTime
                )
            }

            if !XiphChapterUtil.write(chapters, to: url.path) {
                Log.error("Failed to write chapters to \(url.lastPathComponent)")
            }

        case .m4a, .mp4, .aac, .m4b:
            // Nero chpl chapters via TagLib MP4ChapterList
            let chapters = descriptions.map { desc in
                ChapterMarker(
                    name: desc.name ?? "Chapter",
                    startTime: desc.startTime,
                    endTime: desc.endTime ?? desc.startTime
                )
            }

            if !MP4ChapterUtil.write(chapters, to: url.path) {
                Log.error("Failed to write chapters to \(url.lastPathComponent)")
            }

        default:
            Log.debug("Marker writing not supported for \(outputType.rawValue) — skipping")
        }
    }

    // MARK: - Finder Tags

    private func copyFinderTags() {
        do {
            try source.input.copyFinderTags(to: source.output)
        } catch {
            Log.error("Failed to copy Finder tags to \(source.output.lastPathComponent):", error)
        }
    }

    // MARK: - Image

    private func copyImage() {
        do {
            let pictureRef = try TagPictureRef.parsing(url: source.input)

            guard TagPicture.write(pictureRef, path: source.output.path) else {
                Log.error("Failed to write image to \(source.output.lastPathComponent)")
                return
            }
        } catch {
            // Source has no embedded image — expected for many files
        }
    }
}
