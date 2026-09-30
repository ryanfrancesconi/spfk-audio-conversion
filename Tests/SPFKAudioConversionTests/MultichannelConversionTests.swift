// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
class MultichannelConversionTests: BinTestCase {
    // MARK: - M4A

    @Test func sixChannelSourceToM4AKeepsEveryChannel() async throws {
        let input = TestBundleResources.shared.tabla_6_channel
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)
        let sourceChannels = try AVAudioFile(forReading: input).fileFormat.channelCount

        var options = AudioFormatConverterOptions()
        options.format = .m4a
        options.channels = nil

        try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()

        let outputFile = try AVAudioFile(forReading: output)
        #expect(sourceChannels == 6)
        #expect(outputFile.fileFormat.channelCount == sourceChannels)
    }

    /// A plain `WAVE_FORMAT_PCM` header has no channel mask, so nothing downstream can read a
    /// layout from the source.
    @Test func sixChannelSourceWithoutALayoutToM4A() async throws {
        let input = bin.appending(component: "plain6.wav", directoryHint: .notDirectory)
        try Self.writePlainWAV(to: input, channels: 6, sampleRate: 44100, frames: 44100)

        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a

        do {
            try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()
        } catch is AudioFormatConverterError {
            #expect(!output.exists)
            return
        }

        #expect(try AVAudioFile(forReading: output).fileFormat.channelCount == 6)
    }

    /// Writes 16-bit PCM with the 16-byte `fmt ` chunk, which carries no channel layout.
    static func writePlainWAV(to url: URL, channels: Int, sampleRate: Int, frames: Int) throws {
        func le<T: FixedWidthInteger>(_ value: T) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }

        var samples = Data(capacity: frames * channels * 2)
        for frame in 0 ..< frames {
            for channel in 0 ..< channels {
                let hz = 200.0 + 100.0 * Double(channel)
                let value = Int16(8000 * sin(2 * .pi * hz * Double(frame) / Double(sampleRate)))
                samples.append(le(value))
            }
        }

        var fmt = Data()
        fmt.append(le(UInt16(1)))
        fmt.append(le(UInt16(channels)))
        fmt.append(le(UInt32(sampleRate)))
        fmt.append(le(UInt32(sampleRate * channels * 2)))
        fmt.append(le(UInt16(channels * 2)))
        fmt.append(le(UInt16(16)))

        var body = Data("WAVE".utf8)
        body.append(Data("fmt ".utf8) + le(UInt32(fmt.count)) + fmt)
        body.append(Data("data".utf8) + le(UInt32(samples.count)) + samples)

        try (Data("RIFF".utf8) + le(UInt32(body.count)) + body).write(to: url)
    }
}
