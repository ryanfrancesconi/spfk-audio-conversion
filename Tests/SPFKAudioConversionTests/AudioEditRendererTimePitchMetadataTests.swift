// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// What a stretch or transposition rewrites in the render's metadata.
@Suite(.tags(.file))
class AudioEditRendererTimePitchMetadataTests: BinTestCase {
    /// A copy of `tabla.wav` carrying only `tags`, written as another tool would have written them:
    /// the read-path setter stores them verbatim.
    private func source(_ tags: [TagKey: String], fixture: URL = TestBundleResources.shared.tabla_wav) throws -> URL {
        let url = bin.appending(component: "source-\(UUID().uuidString).\(fixture.pathExtension)")
        try FileManager.default.copyItem(at: fixture, to: url)
        try TagProperties.removeAllTags(in: url)

        var properties = TagProperties()
        for (key, value) in tags {
            properties.set(taglibKey: key.taglibKey, value: value)
        }
        try properties.save(to: url)
        return url
    }

    private func render(
        _ source: URL,
        _ timePitch: TimePitchDescription,
        trim: TrimDescription = TrimDescription(),
        scheme: MetadataCopyScheme = .copyAll
    ) async throws -> TagProperties {
        var edit = AudioEditDescription(trim: trim)
        edit.timePitch = timePitch

        let output = bin.appending(component: "out-\(UUID().uuidString).\(source.pathExtension)")
        try await AudioEditRenderer(sourceURL: source, edit: edit, outputURL: output, metadataCopyScheme: scheme).render()
        lastOutput = output
        return try TagProperties(url: output)
    }

    private var lastOutput: URL?

    @Test func theBPMTagIsTheTargetRoundedToTwoDecimals() async throws {
        let tags = try await render(source([.bpm: "120"]), TimePitchDescription(rate: 0.7777))
        #expect(tags[.bpm] == "93.32")
    }

    @Test func aWholeTargetBPMIsWrittenAsAnInteger() async throws {
        let tags = try await render(source([.bpm: "120"]), TimePitchDescription(rate: 0.5))
        #expect(tags[.bpm] == "60")
    }

    @Test func aPitchOnlyRenderKeepsTheBPM() async throws {
        let tags = try await render(source([.bpm: "120", .initialKey: "Am"]), TimePitchDescription(semitones: 2))
        #expect(tags[.bpm] == "120")
        #expect(tags[.initialKey] == "Bm")
    }

    @Test func noBPMIsWrittenWhereTheSourceHadNone() async throws {
        let tags = try await render(source([.title: "x"]), TimePitchDescription(rate: 2))
        #expect(tags[.bpm] == nil)
    }

    @Test(arguments: [
        ("Am", 2, "Bm"),
        ("C# Minor", -1, "Cm"),
        ("Dbm", 2, "Ebm"),
        ("8A", 2, "Bm"),
        ("B", 1, "C"),
        ("Am", 12, "Am"),
    ])
    func theKeyIsTransposedByWholeSemitones(key: String, semitones: Int, expected: String) async throws {
        let tags = try await render(source([.initialKey: key]), TimePitchDescription(semitones: semitones))
        #expect(tags[.initialKey] == expected)
    }

    @Test func centsRoundToTheNearestSemitone() async throws {
        let up = try await render(source([.initialKey: "Am"]), TimePitchDescription(semitones: 1, cents: 60))
        #expect(up[.initialKey] == "Bm")

        let none = try await render(source([.initialKey: "C# Minor"]), TimePitchDescription(cents: 40))
        #expect(none[.initialKey] == "C# Minor")
    }

    @Test func anUnparseableKeyIsLeftAlone() async throws {
        let tags = try await render(source([.initialKey: "varies"]), TimePitchDescription(semitones: 3))
        #expect(tags[.initialKey] == "varies")
    }

    @Test func aCommentKeyMovesToTheKeyTag() async throws {
        let tags = try await render(source([.comment: "8A - Energy 6"]), TimePitchDescription(semitones: 2))
        #expect(tags[.initialKey] == "Bm")
        #expect(tags[.comment] == "Energy 6")
    }

    @Test func aCommentThatWasOnlyTheKeyIsCleared() async throws {
        let tags = try await render(source([.comment: "8A"]), TimePitchDescription(semitones: 2))
        #expect(tags[.initialKey] == "Bm")
        #expect(tags[.comment] == nil || tags[.comment] == "")
    }

    @Test func aRenderIgnoringMetadataRewritesNothing() async throws {
        let source = try source([.bpm: "120", .initialKey: "Am", .comment: "8A - Energy 6"])
        let tags = try await render(source, TimePitchDescription(semitones: 2, rate: 2), scheme: .ignore)

        #expect(tags[.bpm] == nil)
        #expect(tags[.initialKey] == nil)
        #expect(tags[.comment] == nil)
    }

    @Test func markersAreScaledIntoTheStretchedTimeline() async throws {
        let source = try source([:])
        let markers = [
            AudioMarkerDescription(name: "before", startTime: 0.5),
            AudioMarkerDescription(name: "a", startTime: 1.5),
            AudioMarkerDescription(name: "b", startTime: 2.5),
        ]
        #expect(AudioFormatConverter.writeMarkers(markers, to: source, outputType: .wav))

        _ = try await render(source, TimePitchDescription(rate: 2), trim: TrimDescription(inPoint: 1, outPoint: 3))
        let output = try #require(lastOutput)

        let written = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(written.map(\.name) == ["a", "b"])

        for (time, expected) in zip(written.map(\.startTime), [0.25, 0.75]) {
            #expect(abs(time - expected) < 0.001, "\(time)")
        }
    }

    @Test func aRateChangeAloneScalesMarkers() async throws {
        let source = try source([:])
        #expect(AudioFormatConverter.writeMarkers([AudioMarkerDescription(name: "a", startTime: 2)], to: source, outputType: .wav))

        _ = try await render(source, TimePitchDescription(rate: 0.5))
        let output = try #require(lastOutput)

        let written = try await AudioMarkerDescriptionCollection(url: output).markerDescriptions
        #expect(written.count == 1)
        #expect(abs((written.first?.startTime ?? 0) - 4) < 0.001)
    }

    @Test func theIXMLUserBPMIsScaled() async throws {
        let url = bin.appending(component: "ixml.wav")
        try FileManager.default.copyItem(at: TestBundleResources.shared.ixml_chunk, to: url)

        var ixml = try IXMLMetadata(xml: #require(ProductionChunks.readIXML(from: url, fileType: .wav)))
        var fields = ixml.userFields ?? IXMLUserFields()
        fields.bpm = "100"
        ixml.setUserFields(fields)
        try ProductionChunks.writeIXML(ixml.xml, to: url, fileType: .wav)

        _ = try await render(url, TimePitchDescription(rate: 1.5))
        let output = try #require(lastOutput)

        let rendered = try IXMLMetadata(xml: #require(ProductionChunks.readIXML(from: output, fileType: .wav)))
        #expect(rendered.userFields?.bpm == "150")
    }
}
