// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKMatroska
import Testing

@testable import SPFKAudioConversion

/// The sample widths a bundled fixture cannot cover without shipping a file per encoder.
///
/// `tabla_pcm.mka` exercises 24-bit little-endian signed, which is the width `AVAudioPCMBuffer` has
/// no accessor for. Everything else is checked here against values chosen so the expected float is
/// exact.
@Suite
struct MatroskaPCMBlockReaderTests {
    private func widen(_ bytes: [UInt8], _ reader: MatroskaPCMBlockReader) throws -> [Float] {
        let frameCount = bytes.count / reader.bytesPerFrame

        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(reader.channelCount))
        )

        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        )

        reader.write(
            Data(bytes),
            sourceFrameOffset: 0,
            to: buffer,
            destinationFrameOffset: 0,
            frameCount: frameCount
        )

        let data = try #require(buffer.floatChannelData)

        return (0 ..< frameCount).map { data[0][$0] }
    }

    /// 8-bit integer PCM is unsigned, following the WAV convention Matroska inherits — so the
    /// midpoint is 128 rather than 0, and reading it as signed puts silence at full scale.
    @Test func eightBitIsUnsignedAroundOneTwentyEight() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 1, channelCount: 1, sampleFormat: .integer(isBigEndian: false))

        #expect(try widen([128, 0, 192, 64], reader) == [0, -1, 0.5, -0.5])
    }

    @Test func sixteenBitLittleEndianIsSigned() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 2, channelCount: 1, sampleFormat: .integer(isBigEndian: false))

        // 0x0000, 0x4000 (+0.5), 0xC000 (-0.5), 0x8000 (-1.0)
        #expect(try widen([0x00, 0x00, 0x00, 0x40, 0x00, 0xC0, 0x00, 0x80], reader) == [0, 0.5, -0.5, -1])
    }

    /// The same samples byte-reversed must widen to the same floats, which is the whole content of
    /// the `A_PCM/INT/BIG` case.
    @Test func bigEndianReadsTheSameValues() throws {
        let little = MatroskaPCMBlockReader(bytesPerSample: 2, channelCount: 1, sampleFormat: .integer(isBigEndian: false))
        let big = MatroskaPCMBlockReader(bytesPerSample: 2, channelCount: 1, sampleFormat: .integer(isBigEndian: true))

        let littleBytes: [UInt8] = [0x00, 0x40, 0x00, 0xC0]
        let bigBytes: [UInt8] = [0x40, 0x00, 0xC0, 0x00]

        #expect(try widen(littleBytes, little) == widen(bigBytes, big))
    }

    @Test func twentyFourBitSignExtendsFromItsOwnWidth() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 3, channelCount: 1, sampleFormat: .integer(isBigEndian: false))

        // 0x400000 (+0.5) and 0xC00000 (-0.5), which is negative only if the sign bit is read at
        // bit 23 rather than at bit 31.
        #expect(try widen([0x00, 0x00, 0x40, 0x00, 0x00, 0xC0], reader) == [0.5, -0.5])
    }

    @Test func thirtyTwoBitFloatPassesThrough() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 4, channelCount: 1, sampleFormat: .float)

        let values: [Float] = [0, 0.25, -0.75, 1]
        let bytes = values.flatMap { withUnsafeBytes(of: $0.bitPattern.littleEndian) { [UInt8]($0) } }

        #expect(try widen(bytes, reader) == values)
    }

    @Test func sixtyFourBitFloatNarrowsToFloat() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 8, channelCount: 1, sampleFormat: .float)

        let values: [Double] = [0, 0.25, -0.75, 1]
        let bytes = values.flatMap { withUnsafeBytes(of: $0.bitPattern.littleEndian) { [UInt8]($0) } }

        #expect(try widen(bytes, reader) == values.map { Float($0) })
    }

    /// Interleaved in, deinterleaved out.
    @Test func channelsAreSeparated() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 1, channelCount: 2, sampleFormat: .integer(isBigEndian: false))

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))

        // Frames of (left, right): (192, 64) then (64, 192).
        reader.write(
            Data([192, 64, 64, 192]),
            sourceFrameOffset: 0,
            to: buffer,
            destinationFrameOffset: 0,
            frameCount: 2
        )

        let data = try #require(buffer.floatChannelData)

        #expect(data[0][0] == 0.5)
        #expect(data[0][1] == -0.5)
        #expect(data[1][0] == -0.5)
        #expect(data[1][1] == 0.5)
    }

    /// Writing at an offset must not disturb what is already in the buffer, which is what lets a
    /// block be split across two reads.
    @Test func writesAtAnOffsetIntoBothBuffers() throws {
        let reader = MatroskaPCMBlockReader(bytesPerSample: 1, channelCount: 1, sampleFormat: .integer(isBigEndian: false))

        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        let data = try #require(buffer.floatChannelData)

        for index in 0 ..< 4 {
            data[0][index] = 9
        }

        // The third of four source frames, written into the second slot.
        reader.write(
            Data([0, 0, 192, 0]),
            sourceFrameOffset: 2,
            to: buffer,
            destinationFrameOffset: 1,
            frameCount: 1
        )

        #expect(data[0][0] == 9)
        #expect(data[0][1] == 0.5)
        #expect(data[0][2] == 9)
    }
}
