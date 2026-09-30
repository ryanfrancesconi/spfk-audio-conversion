// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKAudioConverterC
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

    // MARK: - Fewer output channels than input

    /// One tone per channel of a 5.1 file, in `kAudioChannelLayoutTag_MPEG_5_1_A` order:
    /// L R C LFE Ls Rs.
    static let surroundTones: [Double] = [440, 660, 1000, 80, 1500, 2100]
    static let centerChannel = 2

    /// Writes a 5.1 float WAV holding ``surroundTones``, one per channel.
    func makeSurroundWAV() throws -> URL {
        let url = bin.appending(component: "surround.wav", directoryHint: .notDirectory)
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layout)
        let frames: AVAudioFrameCount = 48000
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames

        let channels = try #require(buffer.floatChannelData)

        for (channel, hz) in Self.surroundTones.enumerated() {
            for frame in 0 ..< Int(frames) {
                channels[channel][frame] = Float(0.2 * sin(2 * .pi * hz * Double(frame) / 48000))
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)

        return url
    }

    /// Magnitude of `hz` in `samples`, normalized so a full-scale sine reads about 1.
    static func toneLevel(_ samples: [Float], hz: Double, sampleRate: Double) -> Double {
        let coefficient = 2 * cos(2 * .pi * hz / sampleRate)
        var previous = 0.0
        var beforePrevious = 0.0

        for sample in samples {
            let value = Double(sample) + coefficient * previous - beforePrevious
            beforePrevious = previous
            previous = value
        }

        let power = previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious
        return 2 * sqrt(max(0, power)) / Double(samples.count)
    }

    static func channels(of url: URL) throws -> (samples: [[Float]], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)

        let data = try #require(buffer.floatChannelData)
        let samples = (0 ..< Int(buffer.format.channelCount)).map {
            Array(UnsafeBufferPointer(start: data[$0], count: Int(buffer.frameLength)))
        }

        return (samples, file.processingFormat.sampleRate)
    }

    @Test func surroundToFLACKeepsEveryChannel() async throws {
        let input = try makeSurroundWAV()
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        try await AudioFormatConverter(
            inputURL: input,
            outputURL: output,
            options: AudioFormatConverterOptions(format: .flac)
        ).start()

        let (samples, sampleRate) = try Self.channels(of: output)
        try #require(samples.count == Self.surroundTones.count)

        for (channel, hz) in Self.surroundTones.enumerated() {
            #expect(Self.toneLevel(samples[channel], hz: hz, sampleRate: sampleRate) > 0.1, "channel \(channel)")
        }
    }

    @Test(arguments: [AudioFileType.mp3, .wav])
    func surroundToStereoFoldsInTheCenter(format: AudioFileType) async throws {
        let input = try makeSurroundWAV()
        let output = bin.appending(component: "\(#function).\(format.pathExtension)", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions(format: format)
        options.channels = format == .mp3 ? nil : 2

        try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()

        let (samples, sampleRate) = try Self.channels(of: output)
        try #require(samples.count == 2)

        let center = Self.surroundTones[Self.centerChannel]

        for channel in 0 ..< 2 {
            let level = Self.toneLevel(samples[channel], hz: center, sampleRate: sampleRate)
            #expect(level > 0.05, "center tone on output channel \(channel): \(level)")
        }
    }

    @Test func stereoToMonoKeepsTheRightChannel() async throws {
        let input = bin.appending(component: "right.wav", directoryHint: .notDirectory)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
        buffer.frameLength = 48000

        let channels = try #require(buffer.floatChannelData)
        for frame in 0 ..< 48000 {
            channels[0][frame] = 0
            channels[1][frame] = Float(0.2 * sin(2 * .pi * 1000 * Double(frame) / 48000))
        }

        try AVAudioFile(forWriting: input, settings: format.settings).write(from: buffer)

        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)
        var options = AudioFormatConverterOptions(format: .wav)
        options.channels = 1

        try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()

        let (samples, sampleRate) = try Self.channels(of: output)
        try #require(samples.count == 1)
        #expect(Self.toneLevel(samples[0], hz: 1000, sampleRate: sampleRate) > 0.05)
    }

    @Test(arguments: [AudioFileType.ogg, .opus])
    func surroundToOgg(format: AudioFileType) async throws {
        let input = try makeSurroundWAV()
        let output = bin.appending(component: "\(#function).\(format.pathExtension)", directoryHint: .notDirectory)

        try await AudioFormatConverter(
            inputURL: input,
            outputURL: output,
            options: AudioFormatConverterOptions(format: format)
        ).start()

        var sampleRate: Int32 = 0
        var channels: Int32 = 0
        var bitDepth: Int32 = 0
        #expect(SndFileConverter().fileInfo(output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth) == 0)
        #expect(channels == 6)
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
