// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata
import SPFKMetadataBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
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

    // MARK: - Rating Copy Tests

    /// The rating does not travel through TagLib's PropertyMap — it has its own per-format
    /// dispatch — so a tag round-trip on title and artist proves nothing about it.
    @Test(arguments: ["wav", "flac", "mp3", "m4a", "ogg", "opus"])
    func ratingSurvivesConversion(outputExtension: String) async throws {
        let input = TestBundleResources.shared.rated_80_wav
        let sourceStars = try #require(try TagProperties(url: input)[.rating])

        let output = try await convert(input: input, outputExtension: outputExtension)
        #expect(try TagProperties(url: output)[.rating] == sourceStars)
    }

    /// A rating the app saved, rather than one an external tool wrote into the fixture, has to
    /// survive too.
    @Test(arguments: ["flac", "mp3", "m4a", "ogg", "opus"])
    func appWrittenRatingSurvivesConversion(outputExtension: String) async throws {
        let source = bin.appending(
            component: "rated-\(outputExtension).wav", directoryHint: .notDirectory
        )
        if source.exists { try? source.delete() }
        try FileManager.default.copyItem(at: TestBundleResources.shared.tabla_wav, to: source)

        var description = try await MetaAudioFileDescription(parsing: source)
        description.tagProperties[.rating] = "5"
        try description.save(dirtyFlags: [.metadata])
        #expect(try TagProperties(url: source)[.rating] == "5")

        let output = try await convert(input: source, outputExtension: outputExtension)
        #expect(try TagProperties(url: output)[.rating] == "5")
    }

    // MARK: - Image Copy Tests

    @Test func copyAllPreservesImage() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac")

        let artwork = try #require(try EmbeddedArtwork.read(from: output))
        #expect(artwork.cgImage.width == 600)
        #expect(artwork.cgImage.height == 592)
    }

    // MARK: - Scheme Filtering Tests

    @Test func copyTextOnlySkipsMarkers() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "mp3", scheme: .copyText)

        // Tags should be present
        let props = try TagProperties(url: output)
        #expect(props[.title] == "Stonehenge")

        // Markers should not be present
        #expect(try await AudioMarkerDescriptionCollection(url: output).markerDescriptions.isEmpty)
    }

    @Test func ignoreSchemeSkipsAll() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac", scheme: .ignore)

        // Tags should be empty
        let props = try TagProperties(url: output)
        #expect(props[.title] == nil)
        #expect(props[.artist] == nil)

        // Image should not be present
        #expect(try EmbeddedArtwork.read(from: output) == nil)
    }

    // MARK: - Marker Copy Tests

    @Test func copyMarkersMP3ToMP3() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "mp3")

        #expect(try await AudioMarkerDescriptionCollection(url: output).markerDescriptions.count == 3)
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

        let markers = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(markers.map(\.name) == ["M0", "M1", "M2"])
        #expect(markers.map(\.startTime) == [0, 1, 2])
    }

    @Test func copyMarkersMP3ToOGG() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "ogg")

        let markers = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(markers.map(\.name) == ["M0", "M1", "M2"])
        #expect(markers.map(\.startTime) == [0, 1, 2])
    }

    @Test func copyMarkersMP3ToM4A() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "m4a")

        let markers = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(markers.map(\.name) == ["M0", "M1", "M2"])
        #expect(markers.map(\.startTime) == [0, 1, 2])
    }

    @Test func copyMarkersOnlySkipsTagsFLAC() async throws {
        let input = TestBundleResources.shared.mp3_id3
        let output = try await convert(input: input, outputExtension: "flac", scheme: .copyMarkers)

        // Tags should not be present
        let props = try TagProperties(url: output)
        #expect(props[.title] == nil)

        // Markers should be present
        #expect(try await AudioMarkerDescriptionCollection(url: output).markerDescriptions.count == 3)
    }

    // MARK: - XMP handling

    /// XMP lives in an ID3 PRIV frame. `TagProperties.copyTags` copies TagLib's PropertyMap only;
    /// PRIV frames are not in the PropertyMap, so copyAll does not preserve XMP.
    /// This test documents that current behavior.
    ///
    /// When XMP copy is added at a higher layer (outside spfk-audio-conversion), update this expectation.
    @Test func copyAllStripsXMPFromMP3() async throws {
        let input = TestBundleResources.shared.mp3_xmp

        try #require(StoredXMPPacketWrite.storedPacket(in: input) != nil, "Precondition: mp3_xmp must have a PRIV (XMP) frame")

        let output = try await convert(input: input, outputExtension: "mp3")

        #expect(StoredXMPPacketWrite.storedPacket(in: output) == nil, "XMP PRIV frame is stripped — copyTags only copies the PropertyMap")
    }

    // MARK: - Failures reach the caller

    @Test func aMetadataCopyThatFailsIsReported() async throws {
        let input = TestBundleResources.shared.mp3_id3
        #expect(try TagProperties(url: input)[.title] != nil)

        let output = bin.appending(component: "readOnly.mp3", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.tabla_mp3, to: output)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: output.path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: output.path)
        }

        let converter = AudioFormatConverter(
            source: AudioFormatConverterSource(input: input, output: output, options: AudioFormatConverterOptions())
        )

        await converter.copyMetadata()

        let failures = await converter.source.metadataFailures
        #expect(failures.contains { $0.category == .tags }, "\(failures)")
    }

    // MARK: - CAF

    /// Finder tags live in an extended attribute, so they travel whatever the container.
    @Test func finderTagsReachACAFOutput() async throws {
        let input = bin.appending(component: "tagged.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.tabla_wav, to: input)
        try input.set(tagNames: ["Keeper"])

        let output = try await convert(input: input, outputExtension: "caf")

        #expect(output.tagNames.contains("Keeper"))
    }

    // MARK: - A straight copy honors the scheme

    /// A WAV carrying tags, markers, BEXT and a Finder tag, at settings a WAV output would copy
    /// as it is.
    private func makeFullyTaggedWAV() async throws -> URL {
        let input = bin.appending(component: "tagged.wav", directoryHint: .notDirectory)

        try await AudioFormatConverter(
            source: AudioFormatConverterSource(
                input: TestBundleResources.shared.mp3_id3,
                output: input,
                options: AudioFormatConverterOptions(format: .wav)
            )
        ).start()

        let bext = try #require(ProductionChunks.readBEXT(from: TestBundleResources.shared.cowbell_bext_wav, fileType: .wav))
        try ProductionChunks.writeBEXT(bext, to: input, fileType: .wav)
        try input.set(tagNames: ["Private"])

        #expect(try TagProperties(url: input)[.title] == "Stonehenge")
        #expect(try await AudioMarkerDescriptionCollection(url: input).count > 0)
        #expect(ProductionChunks.readBEXT(from: input, fileType: .wav) != nil)

        return input
    }

    @Test func ignoreLeavesEverythingOutOfASameFormatCopy() async throws {
        let input = try await makeFullyTaggedWAV()
        let output = try await convert(input: input, outputExtension: "wav", scheme: .ignore)

        #expect(try TagProperties(url: output)[.title] == nil)
        #expect(ProductionChunks.readBEXT(from: output, fileType: .wav) == nil)
        #expect((try? await AudioMarkerDescriptionCollection(url: output).count) ?? 0 == 0)
        #expect(!output.tagNames.contains("Private"))
    }

    @Test func copyMarkersKeepsOnlyMarkersInASameFormatCopy() async throws {
        let input = try await makeFullyTaggedWAV()
        let output = try await convert(input: input, outputExtension: "wav", scheme: .copyMarkers)

        #expect(try TagProperties(url: output)[.title] == nil)
        #expect(ProductionChunks.readBEXT(from: output, fileType: .wav) == nil)
        #expect(try await AudioMarkerDescriptionCollection(url: output).count > 0)
    }

    /// FLAC keeps BEXT and iXML in APPLICATION blocks, which the tag strip does not reach.
    @Test(arguments: [MetadataCopyScheme.ignore, .copyMarkers])
    func excludingTextRemovesBEXTAndIXMLFromASameFormatFLACCopy(scheme: MetadataCopyScheme) async throws {
        let input = try copyToBin(url: TestBundleResources.shared.flac_bext_ixml_external)
        try #require(ProductionChunks.readBEXT(from: input, fileType: .flac) != nil)
        try #require(ProductionChunks.readIXML(from: input, fileType: .flac) != nil)

        let output = try await convert(input: input, outputExtension: "flac", scheme: scheme)

        #expect(ProductionChunks.readBEXT(from: output, fileType: .flac) == nil)
        #expect(ProductionChunks.readIXML(from: output, fileType: .flac) == nil)
    }

    /// AIFF markers live in `MARK`, outside the tag that excluding text clears.
    @Test func copyMarkersKeepsOnlyMarkersInASameFormatAIFFCopy() async throws {
        let input = try copyToBin(url: TestBundleResources.shared.tabla_aif)
        var props = try TagProperties(url: input)
        props[.title] = "Kept Out"
        try props.save(to: input)

        let inputMarkers = try await AudioMarkerDescriptionCollection(url: input).count
        #expect(inputMarkers > 0)
        #expect(try TagProperties(url: input)[.title] == "Kept Out")

        let output = try await convert(input: input, outputExtension: "aif", scheme: .copyMarkers)

        #expect(try TagProperties(url: output)[.title] == nil)
        #expect(try await AudioMarkerDescriptionCollection(url: output).count == inputMarkers)
    }
}
