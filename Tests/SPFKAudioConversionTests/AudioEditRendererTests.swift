// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKAudioConverterC
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
class AudioEditRendererTests: BinTestCase {
    // MARK: - Helpers

    /// Build a mono WAV file from sample values and return its URL.
    private func makeTempWAV(
        samples: [Float],
        sampleRate: Double = 44100,
        name: String = UUID().uuidString
    ) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, s) in samples.enumerated() {
            buffer.floatChannelData![0][i] = s
        }
        let url = bin.appending(component: "\(name).wav", directoryHint: .notDirectory)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { return [] }
        return (0 ..< Int(buffer.frameLength)).map { data[0][$0] }
    }

    // MARK: - Matroska input

    /// `AVAudioFile` throws `'fmt?'` on a Matroska container, so a pending edit on one has to render
    /// without it, as conversion does.
    ///
    /// `tabla_pcm_mka` holds `tabla.wav` uncompressed, so the render can be checked against the
    /// source rather than only for existing.
    @Test func renderTrimsAMatroskaSource() async throws {
        let source = TestBundleResources.shared.tabla_pcm_mka
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 1, outPoint: 2)),
            outputURL: output,
            fileConflictScheme: .overwrite,
            metadataCopyScheme: .ignore
        )

        try await renderer.render()

        let rendered = try AVAudioFile(forReading: output)
        let expected = rendered.processingFormat.sampleRate

        #expect(rendered.length > 0)
        // One second of it, within a decoder's block of the boundary either side.
        #expect(abs(Double(rendered.length) - expected) < expected * 0.05)
    }

    // MARK: - render()

    @Test func renderInOutPointReducesFrameLength() async throws {
        // 10 frames at 44100 Hz. Keep frames 2–6 (5 frames).
        let sampleRate: Double = 44100
        let source = try makeTempWAV(
            samples: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            sampleRate: sampleRate,
            name: "render_trim_src"
        )
        let output = bin.appending(component: "render_trim_out.wav", directoryHint: .notDirectory)
        let edit = AudioEditDescription(
            trim: TrimDescription(inPoint: 2.0 / sampleRate, outPoint: 7.0 / sampleRate)
        )

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output
        )
        try await renderer.render()

        let result = try AVAudioFile(forReading: output)
        #expect(result.length == 5)

        let out = try readSamples(from: output)
        #expect(out == [2, 3, 4, 5, 6])
    }

    @Test func renderFadeInFirstSampleNearZero() async throws {
        let sampleRate: Double = 44100
        let fadeInSamples = Int(sampleRate * 0.1)
        let samples = Array(repeating: Float(1.0), count: fadeInSamples * 2)

        let source = try makeTempWAV(
            samples: samples,
            sampleRate: sampleRate,
            name: "render_fadein_src"
        )
        let output = bin.appending(component: "render_fadein_out.wav", directoryHint: .notDirectory)
        let edit = AudioEditDescription(fade: FadeDescription(inTime: 0.1))

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output
        )
        try await renderer.render()

        let out = try readSamples(from: output)
        #expect(out[0] < 0.1, "first sample should be near 0 for a fade-in")
        #expect(out[fadeInSamples - 1] > 0.9, "last fade-in sample should be near 1")
    }

    @Test func renderPreservesFormatSettings() async throws {
        // Source is 44100 Hz mono — output should preserve sample rate and channel count.
        let source = try makeTempWAV(
            samples: [Float](repeating: 0.5, count: 1000),
            sampleRate: 44100,
            name: "render_format_src"
        )
        let output = bin.appending(component: "render_format_out.wav", directoryHint: .notDirectory)
        let edit = AudioEditDescription(fade: FadeDescription(inTime: 0.01))

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output
        )
        try await renderer.render()

        let resultFile = try AVAudioFile(forReading: output)
        #expect(resultFile.fileFormat.sampleRate == 44100)
        #expect(resultFile.fileFormat.channelCount == 1)
    }

    @Test func renderThrowsOnConflictWithErrorScheme() async throws {
        let source = try makeTempWAV(
            samples: [0.1, 0.2, 0.3],
            sampleRate: 44100,
            name: "render_conflict_src"
        )
        // Write a file at the output path first so it already exists.
        let output = try makeTempWAV(
            samples: [0.0],
            sampleRate: 44100,
            name: "render_conflict_out"
        )
        let edit = AudioEditDescription(fade: FadeDescription(inTime: 0.01))

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            fileConflictScheme: .error
        )

        await #expect(throws: (any Error).self) {
            try await renderer.render()
        }
    }

    @Test func renderOverwriteSchemeReplacesFile() async throws {
        let source = try makeTempWAV(
            samples: [Float](repeating: 0.5, count: 100),
            sampleRate: 44100,
            name: "render_overwrite_src"
        )
        let output = try makeTempWAV(
            samples: [0.0],
            sampleRate: 44100,
            name: "render_overwrite_out"
        )
        let edit = AudioEditDescription(fade: FadeDescription(inTime: 0.001))

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: edit,
            outputURL: output,
            fileConflictScheme: .overwrite
        )

        let resultURL = try await renderer.render()
        let result = try AVAudioFile(forReading: resultURL)
        #expect(result.length == 100)
    }

    @Test func renderUniqueSchemeDoesNotThrowOnConflict() async throws {
        let source = try makeTempWAV(
            samples: [Float](repeating: 0.5, count: 100),
            sampleRate: 44100,
            name: "render_unique_src"
        )
        let output = try makeTempWAV(
            samples: [0.0],
            sampleRate: 44100,
            name: "render_unique_out"
        )

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(fade: FadeDescription(inTime: 0.001)),
            outputURL: output,
            fileConflictScheme: .unique
        )

        let resultURL = try await renderer.render()
        // The returned URL must be different from the original (a new unique path was chosen)
        #expect(resultURL != output)
        #expect(resultURL.exists)
    }

    // MARK: - MP3 source → MP3 output

    /// Trim an MP3 source and write back to MP3 — the actual failing scenario in the app.
    /// Regression: output was 0-length or corrupted because the trim path was not tested.
    @Test func renderMP3TrimToMP3ProducesNonEmptyFile() async throws {
        let source = TestBundleResources.shared.mp3_id3
        let output = bin.appending(component: "render_mp3_trim_out.mp3", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 2.0)),
            outputURL: output
        )
        try await renderer.render()

        let result = try AVAudioFile(forReading: output)
        #expect(result.length > 0, "MP3 trim output must contain audio frames; got length=\(result.length)")
    }

    // MARK: - Trim across formats

    /// Verifies that trim-to-same-format produces a non-empty file for every format in
    /// TestBundleResources.formats. Covers the regression where MP3 trim produced a 0-length
    /// output due to an unfinalised WAV RIFF header in the intermediate write path.
    @Test(arguments: TestBundleResources.shared.formats)
    func renderTrimToSameFormatProducesNonEmptyFile(source: URL) async throws {
        let ext = source.pathExtension
        let output = bin.appending(
            component: "render_trim_\(source.deletingPathExtension().lastPathComponent)_out.\(ext)",
            directoryHint: .notDirectory
        )
        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 2.0)),
            outputURL: output
        )
        try await renderer.render()

        let result = try AVAudioFile(forReading: output)
        #expect(result.length > 0, "Trim output must contain audio frames for .\(ext); got length=\(result.length)")
    }

    // MARK: - Metadata preservation

    /// mp3_id3 has embedded artwork (600×592). Rendering should preserve the image.
    @Test func renderPreservesEmbeddedImage() async throws {
        let source = TestBundleResources.shared.mp3_id3
        let output = bin.appending(component: "render_image_out.mp3", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(fade: FadeDescription(inTime: 0.01)),
            outputURL: output
        )
        try await renderer.render()

        let artwork = try #require(try EmbeddedArtwork.read(from: output))
        #expect(artwork.cgImage.width == 600)
        #expect(artwork.cgImage.height == 592)
    }

    // MARK: - Marker adjustment on trim

    /// mp3_id3 has chapters at t=0, 1, 2. Trimming inPoint=0.5 removes the t=0 chapter
    /// and shifts the remaining two to t=0.5 and t=1.5.
    @Test func renderInPointTrimCropsAndShiftsMarkers() async throws {
        let source = TestBundleResources.shared.mp3_id3
        let output = bin.appending(component: "render_marker_in_out.mp3", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5)),
            outputURL: output
        )
        try await renderer.render()

        let markers = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(markers.map(\.startTime) == [0.5, 1.5])
    }

    /// mp3_id3 has chapters at t=0, 1, 2. Trimming outPoint=1.5 removes the t=2 chapter;
    /// the remaining two stay at t=0 and t=1 (no inPoint shift).
    @Test func renderOutPointTrimCropsMarkers() async throws {
        let source = TestBundleResources.shared.mp3_id3
        let output = bin.appending(component: "render_marker_out_out.mp3", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(outPoint: 1.5)),
            outputURL: output
        )
        try await renderer.render()

        let markers = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(markers.map(\.startTime) == [0, 1])
    }

    /// Trimming both ends: inPoint=0.5, outPoint=1.5 keeps only the t=1 chapter, shifted to t=0.5.
    @Test func renderInAndOutPointTrimKeepsSingleMarker() async throws {
        let source = TestBundleResources.shared.mp3_id3
        let output = bin.appending(component: "render_marker_both_out.mp3", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 1.5)),
            outputURL: output
        )
        try await renderer.render()

        let markers = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(markers.map(\.startTime) == [0.5])
    }

    // MARK: - M4A image preservation

    /// Copies tabla_m4a to the bin, embeds sharksandwich.jpg, renders it, and verifies the image survives.
    @Test func renderPreservesEmbeddedImageInM4A() async throws {
        let m4a = try copyToBin(url: TestBundleResources.shared.tabla_m4a)

        let imageURL = TestBundleResources.shared.sharksandwich
        let image = try #require(EmbeddedArtwork(contentsOf: imageURL), "Failed to load sharksandwich.jpg")
        let expectedWidth = image.cgImage.width
        let expectedHeight = image.cgImage.height

        try image.write(to: m4a)

        let output = bin.appending(component: "m4a_image_out.m4a", directoryHint: .notDirectory)
        let renderer = AudioEditRenderer(
            sourceURL: m4a,
            edit: AudioEditDescription(fade: FadeDescription(inTime: 0.01)),
            outputURL: output
        )
        try await renderer.render()

        let artwork = try #require(try EmbeddedArtwork.read(from: output))
        #expect(artwork.cgImage.width == expectedWidth)
        #expect(artwork.cgImage.height == expectedHeight)
    }

    // MARK: - XMP handling

    /// XMP lives in an ID3 PRIV frame. AudioEditRenderer routes through AudioFormatConverter
    /// which copies tags via TagLib's PropertyMap only — PRIV frames are not in the PropertyMap,
    /// so XMP is stripped. This test documents that current behavior.
    ///
    /// When XMP copy is added at a higher layer (outside spfk-audio-conversion), update this expectation.
    @Test func renderStripsXMPFromMP3() async throws {
        let source = TestBundleResources.shared.mp3_xmp
        let output = bin.appending(component: "render_xmp_strip_out.mp3", directoryHint: .notDirectory)

        try #require(StoredXMPPacketWrite.storedPacket(in: source) != nil, "Precondition: mp3_xmp must have a PRIV (XMP) frame")

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(fade: FadeDescription(inTime: 0.01)),
            outputURL: output
        )
        try await renderer.render()

        #expect(StoredXMPPacketWrite.storedPacket(in: output) == nil, "XMP PRIV frame is stripped — copyTags only copies the PropertyMap")
    }

    // MARK: - Rendering in place keeps the source's encoding

    @Test func renderKeepsA16BitFLACAt16Bits() async throws {
        let source = bin.appending(component: "source16.flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac
        options.bitsPerChannel = 16
        try await AudioFormatConverter(
            inputURL: TestBundleResources.shared.tabla_wav,
            outputURL: source,
            options: options
        ).start()

        #expect(try Self.fileInfoBitDepth(source) == 16)

        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        try await AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 3.5)),
            outputURL: output
        ).render()

        #expect(try Self.fileInfoBitDepth(output) == 16)
    }

    @Test func renderKeepsAnMP3sBitRate() async throws {
        let source = TestBundleResources.shared.tabla_mp3
        let sourceRate = try await AVAudioFile(forReading: source).estimatedDataRate()
        let output = bin.appending(component: "\(#function).mp3", directoryHint: .notDirectory)

        try await AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 3.5)),
            outputURL: output
        ).render()

        let outputRate = try await AVAudioFile(forReading: output).estimatedDataRate()

        #expect(abs(outputRate - sourceRate) <= 16, "source \(sourceRate) kbps, render \(outputRate) kbps")
    }

    private static func fileInfoBitDepth(_ url: URL) throws -> Int32 {
        var sampleRate: Int32 = 0
        var channels: Int32 = 0
        var bitDepth: Int32 = 0

        guard SndFileConverter().fileInfo(url.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth) == 0 else {
            throw NSError(description: "libsndfile could not open \(url.lastPathComponent)")
        }

        return bitDepth
    }

    // MARK: - Metadata that cannot be carried refuses the render

    /// A render replaces the user's file on Save, so one that lost the file's tags must not be
    /// handed back as a success.
    @Test func aRenderWhoseMetadataCannotBeCopiedThrows() async throws {
        let source = TestBundleResources.shared.mp3_id3
        let output = bin.appending(component: "readOnly.mp3", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.tabla_mp3, to: output)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: output.path)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 1.5)),
            outputURL: output
        )

        await #expect(throws: (any Error).self) {
            try await renderer.carryMetadata(to: output)
        }

        #expect(!output.exists)
    }
}
