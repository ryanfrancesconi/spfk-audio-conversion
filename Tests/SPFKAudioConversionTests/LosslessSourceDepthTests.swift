// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// FLAC and ALAC state their depth in the format flags rather than `mBitsPerChannel`.
@Suite(.tags(.file))
class LosslessSourceDepthTests: BinTestCase {
    /// Whether any sample carries data below the top 16 bits.
    ///
    /// Read as Int32, 24-bit data is left-justified, so bits 0–7 are zero either way; 16-bit data
    /// also leaves bits 8–15 zero, which is what tells the two apart.
    static func holdsMoreThan16Bits(_ url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)

        let channel = try #require(buffer.int32ChannelData?[0])

        return UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            .contains { ($0 >> 8) & 0xFF != 0 }
    }

    @Test func a24BitFLACKeepsItsDepthThroughAResample() async throws {
        let input = TestBundleResources.shared.tabla_flac
        let sourceRate = try AVAudioFile(forReading: input).fileFormat.sampleRate
        #expect(try Self.holdsMoreThan16Bits(input))

        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac
        options.sampleRate = sourceRate == 44100 ? 48000 : 44100
        options.bitsPerChannel = 24

        try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()

        #expect(try Self.holdsMoreThan16Bits(output))
    }
}
