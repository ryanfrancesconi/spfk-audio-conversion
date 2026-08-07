// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKMatroska
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// FLAC and PCM in Matroska, held to `tabla.wav` sample for sample.
///
/// A lossless codec makes that possible where AAC does not: the same audio comes back at the same
/// length with nothing shifted, so a wrong stream description shows up as a mismatch rather than as
/// a correlation that has to be interpreted.
@Suite(.tags(.file), .serialized)
struct MatroskaLosslessDecodeTests {
    private func decodeAll(_ url: URL) throws -> [[Float]] {
        let decoder = try MatroskaAudioDecoder(url: url)
        var channels: [[Float]] = Array(
            repeating: [],
            count: Int(decoder.processingFormat.channelCount)
        )

        while let buffer = try decoder.nextBuffer() {
            guard let data = buffer.floatChannelData else { continue }

            for channel in channels.indices {
                channels[channel].append(
                    contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength))
                )
            }
        }

        return channels
    }

    /// `tabla.wav`, read through AVFoundation, as the reference every fixture below encodes.
    private func referenceChannels() throws -> [[Float]] {
        let file = try AVAudioFile(forReading: TestBundleResources.shared.tabla_wav)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )

        try file.read(into: buffer)

        let data = try #require(buffer.floatChannelData)

        return (0 ..< Int(buffer.format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
        }
    }

    /// The largest absolute difference between two channel sets, and where it is.
    private func largestDifference(_ decoded: [[Float]], _ reference: [[Float]]) -> (value: Float, frame: Int) {
        var largest: Float = 0
        var frame = 0

        for channel in 0 ..< min(decoded.count, reference.count) {
            for index in 0 ..< min(decoded[channel].count, reference[channel].count) {
                let difference = abs(decoded[channel][index] - reference[channel][index])

                if difference > largest {
                    largest = difference
                    frame = index
                }
            }
        }

        return (largest, frame)
    }

    // MARK: - FLAC

    @Test func decodesFLACLosslessly() throws {
        let reference = try referenceChannels()
        let decoded = try decodeAll(TestBundleResources.shared.tabla_flac_mka)

        #expect(decoded.count == reference.count)
        #expect(decoded[0].count == reference[0].count)

        let (difference, frame) = largestDifference(decoded, reference)

        // Lossless means identical, not close: both sides are the same 24-bit samples scaled into
        // float by the same power of two.
        #expect(difference == 0, "largest difference \(difference) at frame \(frame)")
    }

    @Test func flacRunsToTheDeclaredLength() throws {
        let decoder = try MatroskaAudioDecoder(url: TestBundleResources.shared.tabla_flac_mka)
        let reference = try AVAudioFile(forReading: TestBundleResources.shared.tabla_wav)

        #expect(decoder.processingFormat.sampleRate == reference.fileFormat.sampleRate)

        let decoded = try decodeAll(TestBundleResources.shared.tabla_flac_mka)

        // No encoder priming, unlike every lossy sibling in the series.
        #expect(decoded[0].count == Int(reference.length))
    }

    @Test func seeksIntoFLACWithoutDrift() throws {
        let reference = try referenceChannels()
        let decoder = try MatroskaAudioDecoder(url: TestBundleResources.shared.tabla_flac_mka)

        let target = AVAudioFramePosition(1.5 * decoder.processingFormat.sampleRate)

        try decoder.seek(toFrame: target)

        #expect(decoder.framePosition == target)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 4096)
        )

        let read = try decoder.readNextChunk(into: buffer, frameCount: 4096)
        let samples = try #require(buffer.floatChannelData)

        #expect(read == 4096)

        var largest: Float = 0

        for index in 0 ..< Int(read) {
            largest = max(largest, abs(samples[0][index] - reference[0][Int(target) + index]))
        }

        // A seek into a lossless stream lands on the sample it named, so this is exact too.
        #expect(largest == 0, "largest difference \(largest) after seeking to \(target)")
    }

    // MARK: - PCM

    @Test func decodesPCMLosslessly() throws {
        let reference = try referenceChannels()
        let decoded = try decodeAll(TestBundleResources.shared.tabla_pcm_mka)

        #expect(decoded.count == reference.count)
        #expect(decoded[0].count == reference[0].count)

        let (difference, frame) = largestDifference(decoded, reference)

        #expect(difference == 0, "largest difference \(difference) at frame \(frame)")
    }

    /// A PCM block holds whatever the muxer chose rather than a packet's worth, so it need not fit
    /// the buffer a caller asked for and the remainder has to survive between calls.
    @Test func pcmHonorsTheRequestedFrameCount() throws {
        let decoder = try MatroskaAudioDecoder(url: TestBundleResources.shared.tabla_pcm_mka)
        let reference = try referenceChannels()

        var collected: [Float] = []

        while let buffer = try decoder.nextBuffer(frameCapacity: 1000) {
            #expect(buffer.frameLength <= 1000)

            guard let data = buffer.floatChannelData else { continue }

            collected.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }

        #expect(collected.count == reference[0].count)
        #expect(collected == reference[0])
    }

    @Test func seeksIntoPCM() throws {
        let reference = try referenceChannels()
        let decoder = try MatroskaAudioDecoder(url: TestBundleResources.shared.tabla_pcm_mka)

        let target = AVAudioFramePosition(2 * decoder.processingFormat.sampleRate)

        try decoder.seek(toFrame: target)

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 2048)
        )

        let read = try decoder.readNextChunk(into: buffer, frameCount: 2048)
        let samples = try #require(buffer.floatChannelData)

        #expect(read == 2048)

        var largest: Float = 0

        for index in 0 ..< Int(read) {
            largest = max(largest, abs(samples[0][index] - reference[0][Int(target) + index]))
        }

        #expect(largest == 0, "largest difference \(largest) after seeking to \(target)")
    }

    // MARK: - Both

    /// The lossy siblings stay covered: AAC is what `tabla.mka` and `sample.mkv` exercise.
    @Test func everyBundledMatroskaAudioTrackDecodes() throws {
        for url in [
            TestBundleResources.shared.tabla_mka,
            TestBundleResources.shared.tabla_flac_mka,
            TestBundleResources.shared.tabla_pcm_mka,
        ] {
            let decoded = try decodeAll(url)

            #expect(decoded[0].isEmpty == false, "\(url.lastPathComponent) decoded nothing")
            #expect(decoded[0].contains { $0 != 0 }, "\(url.lastPathComponent) decoded silence")
        }
    }
}
