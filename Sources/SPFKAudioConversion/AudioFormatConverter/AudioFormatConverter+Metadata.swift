// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataC
import SPFKMetadataXMP

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
            copyXMP()
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
        }
    }

    // MARK: - BEXT (WAV → WAV only)

    private func copyBEXT(inputType: AudioFileType?, outputType: AudioFileType) {
        guard inputType == .wav, outputType == .wav else { return }

        guard let bext = BEXTDescription(url: source.input) else { return }

        do {
            try BEXTDescription.write(bextDescription: bext, to: source.output)
        } catch {
            Log.error("Failed to copy BEXT to \(source.output.lastPathComponent):", error)
        }
    }

    // MARK: - iXML (WAV → WAV only)

    private func copyIXML(inputType: AudioFileType?, outputType: AudioFileType) {
        guard inputType == .wav, outputType == .wav else { return }

        let sourceFile = WaveFileC(path: source.input.path)
        guard sourceFile.load(), let ixml = sourceFile.iXML else { return }

        let destFile = WaveFileC(path: source.output.path)
        guard destFile.load() else {
            Log.error("Failed to open \(source.output.lastPathComponent) for iXML writing")
            return
        }

        destFile.iXML = ixml
        destFile.markersNeedsSave = false
        destFile.imageNeedsSave = false

        if !destFile.save() {
            Log.error("Failed to write iXML to \(source.output.lastPathComponent)")
        }
    }

    // MARK: - XMP

    private func copyXMP() {
        do {
            let xmpString = try XMP.shared.parse(url: source.input)
            try XMP.shared.write(string: xmpString, to: source.output)
        } catch {
            // Most files won't have XMP — this is expected, not an error worth logging
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

        switch outputType {
        case .wav, .w64, .aiff, .aifc:
            // RIFF cue points via AudioToolbox
            let audioMarkers = collection.markerDescriptions.enumerated().map { i, desc in
                AudioMarker(
                    name: desc.name ?? "Marker",
                    time: desc.startTime,
                    sampleRate: desc.sampleRate ?? 0,
                    markerID: Int32(i)
                )
            }

            if !AudioMarkerUtil.update(source.output, markers: audioMarkers) {
                Log.error("Failed to write markers to \(source.output.lastPathComponent)")
            }

        case .mp3:
            // ID3 CHAP frames via TagLib
            let chapters = collection.markerDescriptions.map { desc in
                ChapterMarker(
                    name: desc.name ?? "Chapter",
                    startTime: desc.startTime,
                    endTime: desc.endTime ?? desc.startTime
                )
            }

            if !MPEGChapterUtil.update(source.output.path, chapters: chapters) {
                Log.error("Failed to write chapters to \(source.output.lastPathComponent)")
            }

        case .flac, .ogg, .opus:
            // Vorbis comment chapters via TagLib XiphComment
            let chapters = collection.markerDescriptions.map { desc in
                ChapterMarker(
                    name: desc.name ?? "Chapter",
                    startTime: desc.startTime,
                    endTime: desc.endTime ?? desc.startTime
                )
            }

            if !XiphChapterUtil.update(source.output.path, chapters: chapters) {
                Log.error("Failed to write chapters to \(source.output.lastPathComponent)")
            }

        default:
            // TODO: Implement marker writing for M4A (TagLib PR)
            Log.debug("Marker writing not supported for \(outputType.rawValue) — skipping")
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
