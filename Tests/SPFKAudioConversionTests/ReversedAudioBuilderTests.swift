// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file, .reverse), .serialized)
final class ReversedAudioBuilderTests: BinTestCase {
    private static let sources: [URL] = [
        TestBundleResources.shared.tabla_wav,
        TestBundleResources.shared.tabla_flac,
        TestBundleResources.shared.tabla_mp3,
        TestBundleResources.shared.tabla_ogg,
        TestBundleResources.shared.tabla_mka,
    ]

    /// The source decoded forwards through the route the builder takes, whole.
    private func decodeForward(_ url: URL) async throws -> [[Float]] {
        var channels: [[Float]] = []

        func append(_ chunk: AVAudioPCMBuffer) throws {
            let data = try #require(chunk.floatChannelData)
            if channels.isEmpty { channels = Array(repeating: [], count: Int(chunk.format.channelCount)) }
            for ch in channels.indices {
                channels[ch] += UnsafeBufferPointer(start: data[ch], count: Int(chunk.frameLength))
            }
        }

        if let decoder = try await TrackPCMSource.source(for: url, audioTrack: nil) {
            let chunk = try #require(AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 4096))
            while true {
                chunk.frameLength = try decoder.readNextChunk(into: chunk, frameCount: 4096)
                guard chunk.frameLength > 0 else { break }
                try append(chunk)
            }
        } else {
            let file = try AVAudioFile(forReading: url)
            let chunk = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
            while true {
                try ReversedAudioBuilder.readToEnd(file, into: chunk, frameCount: 4096)
                guard chunk.frameLength > 0 else { break }
                try append(chunk)
            }
        }

        return channels
    }

    private func readAll(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let data = try #require(buffer.floatChannelData)
        return (0 ..< Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: Int(buffer.frameLength))) }
    }

    @Test(arguments: sources)
    func buildIsTheReversedDecode(source: URL) async throws {
        deleteBinOnExit = true
        let destination = bin.appendingPathComponent("\(source.lastPathComponent).reversed.caf")

        let result = try await ReversedAudioBuilder.build(source: source, audioTrack: nil, into: destination)

        let forward = try await decodeForward(source)
        let reversed = try readAll(destination)

        #expect(result.frameCount == forward[0].count, "\(source.lastPathComponent)")
        #expect(reversed.count == forward.count)
        for ch in forward.indices {
            #expect(reversed[ch] == Array(forward[ch].reversed()), "\(source.lastPathComponent) channel \(ch)")
        }
    }

    @Test func chunkedEqualsWholeAtALengthThatIsNotAMultiple() async throws {
        deleteBinOnExit = true
        let source = TestBundleResources.shared.tabla_wav
        let destination = bin.appendingPathComponent("chunked.caf")

        let result = try await ReversedAudioBuilder.build(source: source, audioTrack: nil, into: destination, chunkFrames: 1000, progress: { _ in })
        #expect(result.frameCount % 1000 != 0)

        let file = try AVAudioFile(forReading: source)
        let whole = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: whole)
        let reference = try whole.reverse()
        let data = try #require(reference.floatChannelData)

        let reversed = try readAll(destination)
        for ch in reversed.indices {
            #expect(reversed[ch] == Array(UnsafeBufferPointer(start: data[ch], count: Int(reference.frameLength))))
        }
    }

    @Test func cancellationDeletesBothTemporaryFiles() async throws {
        deleteBinOnExit = true
        let directory = bin.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("cancelled.caf")

        // A child task, so the cancel reaches the build and not the test itself.
        let build = Task {
            try await ReversedAudioBuilder.build(
                source: TestBundleResources.shared.tabla_wav,
                audioTrack: nil,
                into: destination,
                chunkFrames: 1000,
                progress: { value in
                    // Partway into the second pass, so both files exist.
                    if value > 0.75 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await build.value
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
