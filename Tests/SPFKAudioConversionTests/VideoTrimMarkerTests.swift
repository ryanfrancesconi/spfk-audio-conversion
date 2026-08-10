// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKMetadataC
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

/// Markers across a video trim, end to end.
///
/// The unit tests in `spfk-metadata-base` cover where a marker lands; these cover that it lands
/// there in a real file, and that a trim leaving no markers clears the render's chapter track
/// instead of letting the export's survive at pre-trim times.
@Suite(.tags(.file), .serialized)
final class VideoTrimMarkerTests: BinTestCase {
    /// `sample.mov` runs 2.0s — `ffprobe -show_entries format=duration`, 2026-08-10.
    private let sourceDuration: TimeInterval = 2.0

    private func chapters(of url: URL) -> [ChapterMarker] {
        MP4ChapterUtil.read(url.path) as? [ChapterMarker] ?? []
    }

    private func sourceCopy(named name: String, markers: [AudioMarkerDescription]) throws -> URL {
        let url = bin.appendingPathComponent(name)
        try FileManager.default.copyItem(at: TestBundleResources.shared.sample_mov, to: url)
        AudioFormatConverter.writeMarkers(markers, to: url, outputType: .mov)
        return url
    }

    @Test func aTrimmedVideoKeepsTheMarkersInsideItAtTheirNewTimes() async throws {
        let markers = [
            AudioMarkerDescription(name: "beforeIn", startTime: 0.25),
            AudioMarkerDescription(name: "inside", startTime: 1.0),
            AudioMarkerDescription(name: "afterOut", startTime: 1.8),
        ]

        let source = try sourceCopy(named: "source.mov", markers: markers)
        #expect(chapters(of: source).count == 3)

        let trim = TrimDescription(inPoint: 0.5, outPoint: 1.5)
        let rendered = bin.appendingPathComponent("rendered.mov")

        try await VideoEditRenderer(sourceURL: source, trim: trim, outputURL: rendered).render()

        let renderedDuration = try await AVURLAsset(url: rendered).load(.duration).seconds
        #expect(abs(renderedDuration - 1.0) < 0.1)

        let adjusted = AudioMarkerDescription.adjustedForTrim(
            markers,
            inPoint: trim.inPoint,
            outPoint: trim.outPoint,
            newDuration: renderedDuration
        )

        AudioFormatConverter.writeMarkers(adjusted, to: rendered, outputType: .mov)

        let readBack = chapters(of: rendered)
        #expect(readBack.compactMap(\.name) == ["inside"])

        let start = try #require(readBack.first?.startTime)
        #expect(abs(start - 0.5) < 0.05)
    }

    /// A region spanning the in-point is clipped to the trimmed timeline rather than dropped, and
    /// survives the round trip through the file.
    @Test func aRegionSpanningTheInPointIsWrittenFromZero() async throws {
        let markers = [AudioMarkerDescription(name: "spans", startTime: 0.25, endTime: 1.2)]
        let source = try sourceCopy(named: "region-source.mov", markers: markers)

        let trim = TrimDescription(inPoint: 0.5, outPoint: sourceDuration)
        let rendered = bin.appendingPathComponent("region-rendered.mov")

        try await VideoEditRenderer(sourceURL: source, trim: trim, outputURL: rendered).render()

        let renderedDuration = try await AVURLAsset(url: rendered).load(.duration).seconds

        let adjusted = AudioMarkerDescription.adjustedForTrim(
            markers,
            inPoint: trim.inPoint,
            outPoint: trim.outPoint,
            newDuration: renderedDuration
        )

        #expect(adjusted.first?.startTime == 0)

        let adjustedEnd = try #require(adjusted.first?.endTime)
        #expect(abs(adjustedEnd - 0.7) < 0.0001)

        AudioFormatConverter.writeMarkers(adjusted, to: rendered, outputType: .mov)

        let readBack = chapters(of: rendered)
        #expect(readBack.compactMap(\.name) == ["spans"])

        let start = try #require(readBack.first?.startTime)
        #expect(abs(start) < 0.05)
    }

    /// A trim that keeps no markers has to *clear* the render, not skip it.
    ///
    /// A passthrough export can carry the source's chapter track across — measured 2026-08-10 on
    /// `sample.mov`, where it survived with its times offset by the leading GOP the export keeps.
    /// The render here is seeded with that same pre-trim track so the removal is what the test
    /// exercises, whichever way the export happens to behave.
    @Test func aTrimThatKeepsNoMarkersClearsTheRendersChapterTrack() async throws {
        let markers = [
            AudioMarkerDescription(name: "beforeIn", startTime: 0.1),
            AudioMarkerDescription(name: "afterOut", startTime: 1.9),
        ]

        let source = try sourceCopy(named: "empty-source.mov", markers: markers)

        let trim = TrimDescription(inPoint: 0.5, outPoint: 1.5)
        let rendered = bin.appendingPathComponent("empty-rendered.mov")

        try await VideoEditRenderer(sourceURL: source, trim: trim, outputURL: rendered).render()

        AudioFormatConverter.writeMarkers(markers, to: rendered, outputType: .mov)
        #expect(chapters(of: rendered).isNotEmpty)

        let renderedDuration = try await AVURLAsset(url: rendered).load(.duration).seconds

        let adjusted = AudioMarkerDescription.adjustedForTrim(
            markers,
            inPoint: trim.inPoint,
            outPoint: trim.outPoint,
            newDuration: renderedDuration
        )

        #expect(adjusted.isEmpty)

        AudioFormatConverter.removeMarkers(from: rendered, outputType: .mov)
        #expect(chapters(of: rendered).isEmpty)
    }
}
