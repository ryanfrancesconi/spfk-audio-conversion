// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKMetadataC
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class MetadataCopyTests: BinTestCase {
    // MARK: - Helpers

    func convert(
        input: URL,
        outputExtension: String,
        scheme: MetadataCopyScheme = .copyAll
    ) async throws -> URL {
        let output = bin.appending(component: "\(#function).\(outputExtension)", directoryHint: .notDirectory)
        let source = AudioFormatConverterSource(
            input: input,
            output: output,
            options: AudioFormatConverterOptions(),
            metadataCopyScheme: scheme
        )
        let converter = AudioFormatConverter(source: source)
        try await converter.start()
        #expect(output.exists)
        return output
    }

    // MARK: - Tag Copy Tests

    @Test func copyAllPreservesTagsMP3ToWAV() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "wav")

        let props = try TagProperties(url: output)
        #expect(props[.title] == "Stonehenge")
        #expect(props[.artist] == "Spinal Tap")
    }

    @Test func copyAllPreservesTagsMP3ToFLAC() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac")

        let props = try TagProperties(url: output)
        #expect(props[.title] == "Stonehenge")
        #expect(props[.artist] == "Spinal Tap")
    }

    // MARK: - Image Copy Tests

    @Test func copyAllPreservesImage() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac")

        let pictureRef = try TagPictureRef.parsing(url: output)
        #expect(pictureRef.cgImage.width == 600)
        #expect(pictureRef.cgImage.height == 592)
    }

    // MARK: - Scheme Filtering Tests

    @Test func copyTextOnlySkipsMarkers() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "mp3", scheme: .copyText)

        // Tags should be present
        let props = try TagProperties(url: output)
        #expect(props[.title] == "Stonehenge")

        // Markers should not be present
        let chapters = MPEGChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.isEmpty)
    }

    @Test func ignoreSchemeSkipsAll() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac", scheme: .ignore)

        // Tags should be empty
        let props = try TagProperties(url: output)
        #expect(props[.title] == nil)
        #expect(props[.artist] == nil)

        // Image should not be present
        let picture = TagPicture(path: output.path)?.pictureRef
        #expect(picture == nil)
    }

    // MARK: - Marker Copy Tests

    @Test func copyMarkersMP3ToMP3() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "mp3")

        let chapters = MPEGChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 3)
    }

    @Test func copyMarkersWAVToWAV() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = try await convert(input: input, outputExtension: "wav")

        let collection = try await AudioMarkerDescriptionCollection(url: output)
        let sourceCollection = try await AudioMarkerDescriptionCollection(url: input)
        #expect(collection.count == sourceCollection.count)
        #expect(collection.count > 0)
    }

    @Test func copyMarkersMP3ToFLAC() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac")

        let chapters = XiphChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 3)
        #expect(chapters.map { $0.name } == ["M0", "M1", "M2"])
        #expect(chapters.map { $0.startTime } == [0, 1, 2])
    }

    @Test func copyMarkersMP3ToOGG() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "ogg")

        let chapters = XiphChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 3)
        #expect(chapters.map { $0.name } == ["M0", "M1", "M2"])
        #expect(chapters.map { $0.startTime } == [0, 1, 2])
    }

    @Test func copyMarkersMP3ToM4A() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "m4a")

        let chapters = MP4ChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 3)
        #expect(chapters.map { $0.name } == ["M0", "M1", "M2"])
        #expect(chapters.map { $0.startTime } == [0, 1, 2])
    }

    @Test func copyMarkersMP3ToMP4() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "mp4")

        let chapters = MP4ChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 3)
        #expect(chapters.map { $0.name } == ["M0", "M1", "M2"])
        #expect(chapters.map { $0.startTime } == [0, 1, 2])
    }

    @Test func copyMarkersOnlySkipsTagsFLAC() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac", scheme: .copyMarkers)

        // Tags should not be present
        let props = try TagProperties(url: output)
        #expect(props[.title] == nil)

        // Markers should be present
        let chapters = XiphChapterUtil.chapters(in: output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 3)
    }
}
