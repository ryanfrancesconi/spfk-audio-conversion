// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
class SegmentDividerTests: BinTestCase {
    // Three equal-length segments separated by silence: audio, silence, audio, silence, audio
    // Total: 3 × 4410 audio + 2 × 8820 silence = 30870 frames at 44100 Hz (~0.7 s)
    private let sampleRate: Double = 44100
    private let audioLevel: Float = 0.5

    private func makeSourceFile() throws -> URL {
        let (url, _) = try AudioTestFile.make(segments: [
            (4410, audioLevel), // 0.0–0.1 s  segment 1
            (8820, 0.0), // 0.1–0.3 s  silence
            (4410, audioLevel), // 0.3–0.4 s  segment 2
            (8820, 0.0), // 0.4–0.6 s  silence
            (4410, audioLevel), // 0.6–0.7 s  segment 3
        ])
        // Move into bin so it's cleaned up with the test
        let dest = bin.appending(component: "source.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: url, to: dest)
        try FileManager.default.removeItem(at: url)
        return dest
    }

    private let segments: [TrimDescription] = [
        TrimDescription(inPoint: 0.0, outPoint: 0.1),
        TrimDescription(inPoint: 0.3, outPoint: 0.4),
        TrimDescription(inPoint: 0.6, outPoint: 0.7),
    ]

    // MARK: - Empty

    @Test("divide() returns empty array for empty segment list")
    func emptySegmentsReturnsEmpty() async throws {
        let sourceURL = try makeSourceFile()
        let divider = SegmentDivider(sourceURL: sourceURL, segments: [], outputDirectory: bin)
        let result = try await divider.divide()
        #expect(result.isEmpty)
    }

    // MARK: - Output count

    @Test("divide() produces one file per segment")
    func outputCountMatchesSegmentCount() async throws {
        let sourceURL = try makeSourceFile()
        let divider = SegmentDivider(sourceURL: sourceURL, segments: segments, outputDirectory: bin)
        let result = try await divider.divide()
        #expect(result.count == segments.count)
    }

    // MARK: - Output naming

    @Test("output files are named {stem}_001, _002, _003 with source extension")
    func outputNaming() async throws {
        let sourceURL = try makeSourceFile()
        let divider = SegmentDivider(sourceURL: sourceURL, segments: segments, outputDirectory: bin)
        let result = try await divider.divide()

        #expect(result[0].lastPathComponent == "source_001.wav")
        #expect(result[1].lastPathComponent == "source_002.wav")
        #expect(result[2].lastPathComponent == "source_003.wav")
    }

    // MARK: - Output files exist

    @Test("all output files exist on disk after divide()")
    func outputFilesExist() async throws {
        let sourceURL = try makeSourceFile()
        let divider = SegmentDivider(sourceURL: sourceURL, segments: segments, outputDirectory: bin)
        let result = try await divider.divide()

        for url in result {
            #expect(url.exists, "expected output file at \(url.path)")
        }
    }

    // MARK: - Trim applied

    @Test("each output file has duration matching the segment window")
    func outputFileDurationMatchesSegment() async throws {
        let sourceURL = try makeSourceFile()

        var options = SegmentDividerOptions()
        options.fileConflictScheme = .overwrite

        let divider = SegmentDivider(sourceURL: sourceURL, segments: segments, outputDirectory: bin, options: options)
        let result = try await divider.divide()

        for (index, url) in result.enumerated() {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            let expected = segments[index].outPoint - segments[index].inPoint
            // Allow 5 ms tolerance for de-click fades applied at trim boundaries.
            #expect(abs(duration - expected) < 0.006, "segment \(index): expected ~\(expected)s, got \(duration)s")
        }
    }

    // MARK: - normalizeEach

    @Test("normalizeEach does not crash on audio input")
    func normalizeEachDoesNotCrash() async throws {
        let sourceURL = try makeSourceFile()

        var options = SegmentDividerOptions()
        options.normalizeEach = true

        let divider = SegmentDivider(sourceURL: sourceURL, segments: segments, outputDirectory: bin, options: options)
        let result = try await divider.divide()
        #expect(result.count == segments.count)
    }

    @Test("normalizeEach returns unity gain for near-silent segment without crashing")
    func normalizeEachSilentSegment() async throws {
        let (url, _) = try AudioTestFile.make(segments: [(44100, 0.0)])
        let dest = bin.appending(component: "silent.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: url, to: dest)
        try FileManager.default.removeItem(at: url)

        var options = SegmentDividerOptions()
        options.normalizeEach = true

        let silentSegments = [TrimDescription(inPoint: 0.0, outPoint: 0.5)]
        let divider = SegmentDivider(sourceURL: dest, segments: silentSegments, outputDirectory: bin, options: options)
        let result = try await divider.divide()
        #expect(result.count == 1)
    }

    // MARK: - Markers

    @Test("divide() does not copy source markers to output segments")
    func markersNotCopiedToSegments() async throws {
        let sourceURL = try makeSourceFile()

        // Write "In NN" segment markers to the source so there is something to NOT copy.
        let sourceMarkers = segments.asSegmentMarkers()
        AudioFormatConverter.writeMarkers(sourceMarkers, to: sourceURL, outputType: .wav)

        let sourceCollection = try await AudioMarkerDescriptionCollection(url: sourceURL)
        #expect(sourceCollection.count == segments.count, "precondition: source must have markers")

        var options = SegmentDividerOptions()
        options.fileConflictScheme = .overwrite

        let divider = SegmentDivider(sourceURL: sourceURL, segments: segments, outputDirectory: bin, options: options)
        let result = try await divider.divide()

        for url in result {
            let collection = try await AudioMarkerDescriptionCollection(url: url)
            #expect(collection.count == 0, "\(url.lastPathComponent): expected no markers, found \(collection.count)")
        }
    }

    @Test("divide() writes cue markers to the segment they fall in, adjusted to segment-relative time")
    func cueMarkersWrittenToMatchingSegment() async throws {
        let sourceURL = try makeSourceFile()

        // Cue marker inside segment 2 (0.3–0.4), one outside any segment, and a region
        // marker that should never appear in output (region markers define boundaries).
        let sourceMarkers: [AudioMarkerDescription] = [
            AudioMarkerDescription(name: "Cue A", startTime: 0.35),
            AudioMarkerDescription(name: "Cue B", startTime: 0.55),
            AudioMarkerDescription(name: "Region", startTime: 0.3, endTime: 0.4, markerType: .region),
        ]

        var options = SegmentDividerOptions()
        options.fileConflictScheme = .overwrite

        let divider = SegmentDivider(
            sourceURL: sourceURL,
            segments: segments,
            outputDirectory: bin,
            options: options,
            markers: sourceMarkers
        )
        let result = try await divider.divide()

        // Segment 1 (0.0–0.1): no cues inside → no markers
        let seg1 = try await AudioMarkerDescriptionCollection(url: result[0])
        #expect(seg1.count == 0)

        // Segment 2 (0.3–0.4): "Cue A" at 0.35 → adjusted to 0.05
        let seg2 = try await AudioMarkerDescriptionCollection(url: result[1])
        #expect(seg2.count == 1)
        #expect(seg2.markerDescriptions[0].name == "Cue A")
        #expect(abs(seg2.markerDescriptions[0].startTime - 0.05) < 0.001)

        // Segment 3 (0.6–0.7): no cues inside → no markers
        let seg3 = try await AudioMarkerDescriptionCollection(url: result[2])
        #expect(seg3.count == 0)
    }

    @Test("divide() writes cue markers to converted output format (WAV → AIFF)")
    func cueMarkersWrittenToConvertedOutput() async throws {
        let sourceURL = try makeSourceFile()

        let sourceMarkers: [AudioMarkerDescription] = [
            AudioMarkerDescription(name: "Cue A", startTime: 0.35),
            AudioMarkerDescription(name: "Region", startTime: 0.3, endTime: 0.4, markerType: .region),
        ]

        var options = SegmentDividerOptions()
        options.outputFormat = .aiff
        options.fileConflictScheme = .overwrite

        let divider = SegmentDivider(
            sourceURL: sourceURL,
            segments: segments,
            outputDirectory: bin,
            options: options,
            markers: sourceMarkers
        )
        let result = try await divider.divide()

        #expect(result.count == segments.count)
        #expect(result[1].pathExtension == "aiff")

        // Segment 2 (0.3–0.4): "Cue A" at 0.35 → adjusted to 0.05
        let seg2 = try await AudioMarkerDescriptionCollection(url: result[1])
        #expect(seg2.count == 1)
        #expect(seg2.markerDescriptions[0].name == "Cue A")
        #expect(abs(seg2.markerDescriptions[0].startTime - 0.05) < 0.001)

        // Segment 1 and 3: no cues inside → no markers
        let seg1 = try await AudioMarkerDescriptionCollection(url: result[0])
        #expect(seg1.count == 0)
        let seg3 = try await AudioMarkerDescriptionCollection(url: result[2])
        #expect(seg3.count == 0)
    }

    // MARK: - Output directory default

    @Test("outputDirectory defaults to source file's parent directory")
    func defaultOutputDirectory() async throws {
        let sourceURL = try makeSourceFile()
        let divider = SegmentDivider(sourceURL: sourceURL, segments: [segments[0]])
        #expect(await divider.outputDirectory == sourceURL.deletingLastPathComponent())
    }

    // MARK: - Ordering with > 4 segments

    @Test("output files are returned in segment order when more than 4 segments run concurrently")
    func outputOrderWithSixSegments() async throws {
        // 6 audio bursts — exercises the concurrent task group's index-based ordering
        // (the group caps at 4 in-flight, so tasks 5 and 6 are enqueued after earlier ones complete)
        let (url, _) = try AudioTestFile.make(segments: [
            (4410, audioLevel), (4410, 0.0),
            (4410, audioLevel), (4410, 0.0),
            (4410, audioLevel), (4410, 0.0),
            (4410, audioLevel), (4410, 0.0),
            (4410, audioLevel), (4410, 0.0),
            (4410, audioLevel),
        ])
        let dest = bin.appending(component: "source6.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: url, to: dest)
        try FileManager.default.removeItem(at: url)

        let sixSegments: [TrimDescription] = (0 ..< 6).map { i in
            let start = Double(i) * 0.2
            return TrimDescription(inPoint: start, outPoint: start + 0.1)
        }

        let divider = SegmentDivider(sourceURL: dest, segments: sixSegments, outputDirectory: bin)
        let result = try await divider.divide()

        #expect(result.count == 6)
        for (i, outputURL) in result.enumerated() {
            let expected = String(format: "source6_%03d.wav", i + 1)
            #expect(outputURL.lastPathComponent == expected)
        }
    }
}

// MARK: - SegmentDividerOptions Codable

struct SegmentDividerOptionsTests {
    @Test("SegmentDividerOptions encodes and decodes without data loss")
    func codableRoundTrip() throws {
        var options = SegmentDividerOptions()
        options.normalizeEach = true
        options.fadeInTime = 0.1
        options.fadeOutTime = 0.2
        options.fileConflictScheme = .overwrite

        let data = try JSONEncoder().encode(options)
        let decoded = try JSONDecoder().decode(SegmentDividerOptions.self, from: data)

        #expect(decoded.outputFormat == options.outputFormat)
        #expect(decoded.normalizeEach == options.normalizeEach)
        #expect(decoded.fadeInTime == options.fadeInTime)
        #expect(decoded.fadeOutTime == options.fadeOutTime)
        #expect(decoded.fileConflictScheme == options.fileConflictScheme)
    }

    @Test("SegmentDividerOptions decoding falls back to defaults when all fields are absent")
    func codableMissingFieldsUseDefaults() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SegmentDividerOptions.self, from: data)
        let defaults = SegmentDividerOptions()

        #expect(decoded.outputFormat == defaults.outputFormat)
        #expect(decoded.conversionOptions == nil)
        #expect(decoded.normalizeEach == defaults.normalizeEach)
        #expect(decoded.fadeInTime == defaults.fadeInTime)
        #expect(decoded.fadeOutTime == defaults.fadeOutTime)
        #expect(decoded.fileConflictScheme == defaults.fileConflictScheme)
    }
}
