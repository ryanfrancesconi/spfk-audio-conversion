// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// The milestone that makes ShadowTag want Matroska at all: an audio application showing no
/// waveform for a file is not usable whatever else works.
///
/// `tabla.mka` is `tabla.m4a`'s AAC remuxed with `-c copy`, so the same scan run through
/// AVFoundation is the reference for what the Matroska path should produce.
@Suite(.tags(.file), .serialized)
final class MatroskaWaveformTests {
    let mka = TestBundleResources.shared.tabla_mka
    let m4a = TestBundleResources.shared.tabla_m4a

    private func waveform(matroska url: URL) async throws -> WaveformData {
        let decoder = try MatroskaAudioDecoder(url: url)
        let duration = try #require(decoder.file.duration)

        return try await WaveformDataParser().parse(pcmSource: decoder, url: url, duration: duration)
    }

    @Test func producesAWaveformForAMatroskaFile() async throws {
        let data = try await waveform(matroska: mka)

        #expect(data.floatChannelData.isEmpty == false)
        #expect(data.sampleRate == 48000)
        #expect(data.audioDuration > 4)

        // Real peaks, not an allocated array of zeros -- which is exactly what a scan that reads
        // nothing produces, and it would satisfy every other assertion here.
        let peak = data.floatChannelData[0].max() ?? 0
        #expect(peak > 0.1)
    }

    /// The decisive comparison: the same audio scanned through `AVAudioFile` and through the
    /// demuxer must draw the same waveform.
    ///
    /// Compares the peak envelope statistically rather than point by point — the Matroska stream
    /// keeps the AAC encoder priming that the `.m4a`'s edit list trims, so the two are offset by a
    /// fixed lead-in and identical output would still fail a positional diff.
    @Test func matchesTheWaveformAVFoundationProducesForTheSameAudio() async throws {
        let matroska = try await waveform(matroska: mka)
        let reference = try await WaveformDataParser().parse(url: m4a)

        #expect(matroska.sampleRate == reference.sampleRate)
        #expect(matroska.floatChannelData.count == reference.floatChannelData.count)

        let matroskaChannel = try #require(matroska.floatChannelData.first)
        let referenceChannel = try #require(reference.floatChannelData.first)

        #expect(referenceChannel.max() ?? 0 > 0.1, "the reference must have signal or this proves nothing")

        // Same loudest point.
        let matroskaPeak = matroskaChannel.max() ?? 0
        let referencePeak = referenceChannel.max() ?? 0
        #expect(abs(matroskaPeak - referencePeak) < 0.05)

        // Same overall shape: mean peak height across the whole envelope.
        let matroskaMean = matroskaChannel.reduce(0, +) / Float(matroskaChannel.count)
        let referenceMean = referenceChannel.reduce(0, +) / Float(referenceChannel.count)
        #expect(abs(matroskaMean - referenceMean) / referenceMean < 0.1)

        // The Matroska envelope is longer by exactly the AAC encoder priming: measured at 32 points,
        // and 32 x 64 samples-per-point = 2048 frames, which is the priming an .m4a's edit list
        // trims and a raw packet stream has no way to know about. Asserted as a bound rather than
        // waved away -- growing past one priming allowance would mean frames are being duplicated.
        let extra = matroskaChannel.count - referenceChannel.count
        let onePrimingAllowance = 2112 / WaveformDrawingResolution.medium.samplesPerPoint + 1

        #expect(extra >= 0)
        #expect(extra <= onePrimingAllowance)
    }

    /// Chunking is the adapter's only real job — the decoder emits whole packets while the scan
    /// asks for an exact frame count, so the remainder has to survive between calls.
    @Test func readsExactChunkSizesAcrossPacketBoundaries() throws {
        let decoder = try MatroskaAudioDecoder(url: mka)
        let requested: AVAudioFrameCount = 777 // deliberately not a multiple of AAC's 1024

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: decoder.processingFormat,
                                                   frameCapacity: requested))

        var reads = 0

        while reads < 20 {
            let written = try decoder.readNextChunk(into: buffer, frameCount: requested)
            guard written > 0 else { break }

            #expect(written == requested, "read \(reads) was short before the end of the file")
            #expect(buffer.frameLength == written)
            reads += 1
        }

        #expect(reads == 20)
    }
}
