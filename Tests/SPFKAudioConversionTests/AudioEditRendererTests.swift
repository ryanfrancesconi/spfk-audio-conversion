// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKMetadataC
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

        let pictureRef = try TagPictureRef.parsing(url: output)
        #expect(pictureRef.cgImage.width == 600)
        #expect(pictureRef.cgImage.height == 592)
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

        let chapters = MPEGChapterUtil.read(output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0.5)
        #expect(chapters[1].startTime == 1.5)
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

        let chapters = MPEGChapterUtil.read(output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 2)
        #expect(chapters[0].startTime == 0)
        #expect(chapters[1].startTime == 1)
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

        let chapters = MPEGChapterUtil.read(output.path) as? [ChapterMarker] ?? []
        #expect(chapters.count == 1)
        #expect(chapters[0].startTime == 0.5)
    }

    // MARK: - M4A image preservation

    /// Copies tabla_m4a to the bin, embeds sharksandwich.jpg, renders it, and verifies the image survives.
    @Test func renderPreservesEmbeddedImageInM4A() async throws {
        let m4a = try copyToBin(url: TestBundleResources.shared.tabla_m4a)

        let imageURL = TestBundleResources.shared.sharksandwich
        guard let pictureRef = TagPictureRef(url: imageURL, pictureDescription: "", pictureType: "") else {
            Issue.record("Failed to load sharksandwich.jpg")
            return
        }
        let expectedWidth = pictureRef.cgImage.width
        let expectedHeight = pictureRef.cgImage.height

        let written = TagPicture.write(pictureRef, path: m4a.path)
        #expect(written, "Precondition: image must be writable to M4A")

        let output = bin.appending(component: "m4a_image_out.m4a", directoryHint: .notDirectory)
        let renderer = AudioEditRenderer(
            sourceURL: m4a,
            edit: AudioEditDescription(fade: FadeDescription(inTime: 0.01)),
            outputURL: output
        )
        try await renderer.render()

        let readBack = try TagPictureRef.parsing(url: output)
        #expect(readBack.cgImage.width == expectedWidth)
        #expect(readBack.cgImage.height == expectedHeight)
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

        let sourceID3 = ID3File(path: source.path)
        try #require(sourceID3.load())
        try #require(sourceID3[id3: .private] != nil, "Precondition: mp3_xmp must have a PRIV (XMP) frame")

        let renderer = AudioEditRenderer(
            sourceURL: source,
            edit: AudioEditDescription(fade: FadeDescription(inTime: 0.01)),
            outputURL: output
        )
        try await renderer.render()

        let outputID3 = ID3File(path: output.path)
        #expect(outputID3.load())
        #expect(outputID3[id3: .private] == nil, "XMP PRIV frame is stripped — copyTags only copies the PropertyMap")
    }
}
