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

/// Channel edits render with the channel count they write, a ceiling on integer and lossy output,
/// and a TRACK_LIST describing the new channels.
@Suite(.tags(.file))
class AudioEditRendererChannelTests: BinTestCase {
    private static let operations: [ChannelOperation] = [
        .swap, .mono(.average), .mono(.left), .mono(.right), .midSideDecode(width: 0.8), .midSideEncode,
    ]

    private static let sources: [URL] = {
        let r = TestBundleResources.shared
        return [r.tabla_wav, r.tabla_aif, r.tabla_m4a, r.tabla_mp3, r.tabla_flac]
    }()

    private func output(_ name: String, like source: URL) -> URL {
        bin.appending(component: "\(name).\(source.pathExtension)", directoryHint: .notDirectory)
    }

    private func read(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return buffer
    }

    private func rms(_ buffer: AVAudioPCMBuffer) throws -> Float {
        let data = try #require(buffer.floatChannelData)
        var sum: Double = 0
        for ch in 0 ..< Int(buffer.format.channelCount) {
            for i in 0 ..< Int(buffer.frameLength) {
                sum += Double(data[ch][i] * data[ch][i])
            }
        }
        return Float((sum / Double(Int(buffer.format.channelCount) * Int(buffer.frameLength))).squareRoot())
    }

    // MARK: - Channel count

    @Test(arguments: sources, operations)
    func rendersTheOperationsChannelCount(source: URL, operation: ChannelOperation) async throws {
        let inputChannels = try AVAudioFile(forReading: source).processingFormat.channelCount
        try #require(inputChannels == 2)

        let out = output("rendered", like: source)
        try await AudioEditRenderer(sourceURL: source, edit: AudioEditDescription(channels: operation), outputURL: out).render()

        let file = try AVAudioFile(forReading: out)
        #expect(file.processingFormat.channelCount == operation.outputChannelCount(forInput: inputChannels))
        #expect(try read(out).frameLength > 0)
    }

    // MARK: - Ceiling

    /// A swap is the channel operation; the normalize gain is what drives the peaks over.
    private let clippingEdit = AudioEditDescription(channels: .swap, normalize: NormalizeDescription(gain: 6))

    @Test func ceilingKeepsIntegerOutputUnderFullScale() async throws {
        let source = TestBundleResources.shared.tabla_wav
        var renders: [ClippingCeiling: AVAudioPCMBuffer] = [:]

        for ceiling in ClippingCeiling.allCases {
            let out = output("ceiling-\(ceiling.rawValue)", like: source)
            try await AudioEditRenderer(
                sourceURL: source,
                edit: clippingEdit,
                outputURL: out,
                renderSettings: AudioRenderSettings(ceiling: ceiling)
            ).render()

            let buffer = try read(out)
            #expect(try buffer.peak().amplitude <= 1)
            renders[ceiling] = buffer
        }

        let scaled = try rms(#require(renders[.scale]))
        let limited = try rms(#require(renders[.limit]))
        #expect(limited > scaled)
    }

    @Test func floatOutputKeepsPeaksAboveFullScale() async throws {
        let floatSource = bin.appending(component: "float.wav", directoryHint: .notDirectory)
        let input = try read(TestBundleResources.shared.tabla_wav)
        do {
            let file = try AVAudioFile(forWriting: floatSource, settings: input.format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: input)
        }

        let out = output("float-rendered", like: floatSource)
        try await AudioEditRenderer(sourceURL: floatSource, edit: clippingEdit, outputURL: out).render()

        #expect(try read(out).peak().amplitude > 1)
    }

    @Test func noChannelOperationLeavesNormalizeUnceiled() async throws {
        let floatSource = TestBundleResources.shared.tabla_wav
        let out = output("normalize-only", like: floatSource)
        let edit = AudioEditDescription(normalize: NormalizeDescription(gain: 6))
        try await AudioEditRenderer(sourceURL: floatSource, edit: edit, outputURL: out, renderSettings: AudioRenderSettings(ceiling: .limit)).render()

        // Clipped at the integer conversion, not scaled or limited: much of the signal sits at full scale.
        let buffer = try read(out)
        let data = try #require(buffer.floatChannelData)
        let atFullScale = (0 ..< Int(buffer.frameLength)).filter { abs(data[0][$0]) > 0.999 }.count
        #expect(atFullScale > 100)
    }

    // MARK: - TRACK_LIST

    private func renderedTracks(_ operation: ChannelOperation, source: URL) async throws -> [IXMLMetadata.Track]? {
        let out = output("ixml-\(operation.kindName)", like: source)
        try await AudioEditRenderer(sourceURL: source, edit: AudioEditDescription(channels: operation), outputURL: out).render()
        let xml = try #require(ProductionChunks.readIXML(from: out, fileType: .wav))
        return try IXMLMetadata(xml: xml).tracks
    }

    @Test(arguments: operations)
    func trackListDescribesTheRender(operation: ChannelOperation) async throws {
        let source = TestBundleResources.shared.ixml_chunk
        var expected = try IXMLMetadata(xml: #require(ProductionChunks.readIXML(from: source, fileType: .wav)))
        expected.applyChannelOperation(operation)

        let tracks = try await renderedTracks(operation, source: source)
        #expect(tracks == expected.tracks)
        #expect(tracks?.count == Int(operation.outputChannelCount(forInput: 2)))
    }

    @Test func trackListOfLeftRightSourceFollowsEachOperation() async throws {
        let source = bin.appending(component: "lr.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.ixml_chunk, to: source)

        var ixml = try IXMLMetadata(xml: #require(ProductionChunks.readIXML(from: source, fileType: .wav)))
        ixml.tracks = [
            IXMLMetadata.Track(channelIndex: "3", interleaveIndex: "1", name: "Boom"),
            IXMLMetadata.Track(channelIndex: "5", interleaveIndex: "2", name: "Lav"),
        ]
        try ProductionChunks.writeIXML(ixml.xml, to: source, fileType: .wav)

        typealias Track = IXMLMetadata.Track
        #expect(try await renderedTracks(.swap, source: source) == [
            Track(channelIndex: "5", interleaveIndex: "1", name: "Lav"),
            Track(channelIndex: "3", interleaveIndex: "2", name: "Boom"),
        ])
        #expect(try await renderedTracks(.mono(.average), source: source) == [Track(interleaveIndex: "1", name: "Mono")])
        #expect(try await renderedTracks(.mono(.right), source: source) == [Track(channelIndex: "5", interleaveIndex: "1", name: "Lav")])
        #expect(try await renderedTracks(.midSideEncode, source: source) == [
            Track(channelIndex: "3", interleaveIndex: "1", name: "M", function: "M-MID_SIDE"),
            Track(channelIndex: "5", interleaveIndex: "2", name: "S", function: "S-MID_SIDE"),
        ])
    }

    @Test func sourceWithoutTrackListGetsNone() async throws {
        let source = TestBundleResources.shared.tabla_wav
        let out = output("no-ixml", like: source)
        try await AudioEditRenderer(sourceURL: source, edit: AudioEditDescription(channels: .mono(.average)), outputURL: out).render()
        #expect(ProductionChunks.readIXML(from: source, fileType: .wav) == nil)
        #expect(ProductionChunks.readIXML(from: out, fileType: .wav) == nil)
    }
}

/// A spot's mono conform composes after the edit's own channel operation.
@Suite(.tags(.file))
class AudioEditRendererConformTests: BinTestCase {
    private func channels(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        var result = [[Float]](repeating: [], count: Int(file.processingFormat.channelCount))
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384))
        // A single read can stop short of the end.
        while file.framePosition < file.length {
            try file.read(into: chunk)
            guard chunk.frameLength > 0 else { break }
            let data = try #require(chunk.floatChannelData)
            for ch in result.indices {
                result[ch] += UnsafeBufferPointer(start: data[ch], count: Int(chunk.frameLength))
            }
        }
        return result
    }

    /// `tabla.wav` as float, so the comparison is free of requantization.
    private func floatSource() throws -> URL {
        let url = bin.appending(component: "source.wav", directoryHint: .notDirectory)
        let file = try AVAudioFile(forReading: TestBundleResources.shared.tabla_wav)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        // Scoped, so the WAV header is finalized before the render reads it.
        do {
            let output = try AVAudioFile(forWriting: url, settings: buffer.format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try output.write(from: buffer)
        }
        return url
    }

    private func render(_ source: URL, _ operation: ChannelOperation, conform: MonoSource) async throws -> [[Float]] {
        let out = bin.appending(component: "conformed-\(operation.kindName)-\(conform.rawValue).wav", directoryHint: .notDirectory)
        try await AudioEditRenderer(
            sourceURL: source, edit: AudioEditDescription(channels: operation), outputURL: out, conformToMono: conform
        ).render()
        return try channels(out)
    }

    @Test func swapThenLeftIsTheSourcesRight() async throws {
        let source = try floatSource()
        let original = try channels(source)
        #expect(try await render(source, .swap, conform: .left) == [original[1]])
    }

    @Test func decodeThenAverageIsMid() async throws {
        let source = try floatSource()
        let original = try channels(source)
        let rendered = try await render(source, .midSideDecode(width: 1), conform: .average)
        try #require(rendered.count == 1)
        try #require(rendered[0].count == original[0].count)
        let worst = zip(rendered[0], original[0]).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 1e-6)
    }

    @Test func monoEditIsNotConformedAgain() async throws {
        let source = try floatSource()
        let original = try channels(source)
        #expect(try await render(source, .mono(.right), conform: .left) == [original[1]])
    }

    /// `AVAudioFile` hands a mono float WAV over in two reads; an edit must render all of it.
    @Test func monoFloatSourceRendersWhole() async throws {
        _ = try await render(floatSource(), .none, conform: .left)
        let monoURL = bin.appending(component: "conformed-none-left.wav", directoryHint: .notDirectory)
        let out = bin.appending(component: "renormalized.wav", directoryHint: .notDirectory)
        try await AudioEditRenderer(sourceURL: monoURL, edit: AudioEditDescription(normalize: NormalizeDescription(gain: 0.5)), outputURL: out).render()

        #expect(try AVAudioFile(forReading: out).length == AVAudioFile(forReading: monoURL).length)
    }

    @Test func conformWithoutEditRendersMonoTrackList() async throws {
        let out = bin.appending(component: "ixml-conformed.wav", directoryHint: .notDirectory)
        try await AudioEditRenderer(
            sourceURL: TestBundleResources.shared.ixml_chunk, edit: AudioEditDescription(), outputURL: out, conformToMono: .left
        ).render()

        let xml = try #require(ProductionChunks.readIXML(from: out, fileType: .wav))
        #expect(try IXMLMetadata(xml: xml).tracks?.map(\.name) == ["Mid"])
        #expect(try channels(out).count == 1)
    }
}
