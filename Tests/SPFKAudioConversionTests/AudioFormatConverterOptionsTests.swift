// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct AudioFormatConverterOptionsTests {
    // MARK: - bitsPerChannel clamping

    @Test func bitsPerChannelClampedToMinimum() {
        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = 8
        #expect(options.bitsPerChannel == 16)
    }

    @Test func bitsPerChannelClampedToMaximum() {
        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = 64
        #expect(options.bitsPerChannel == 32)
    }

    @Test func bitsPerChannelAcceptsValidValues() {
        var options = AudioFormatConverterOptions()
        for depth: UInt32 in [16, 24, 32] {
            options.bitsPerChannel = depth
            #expect(options.bitsPerChannel == depth)
        }
    }

    @Test func bitsPerChannelNilByDefault() {
        let options = AudioFormatConverterOptions()
        #expect(options.bitsPerChannel == nil)
    }

    // MARK: - bitRate clamping

    @Test func bitRateClampedToMinimum() {
        var options = AudioFormatConverterOptions()
        options.bitRate = 1000
        #expect(options.bitRate == AudioFormatConverterOptions.bitRateRange.lowerBound)
    }

    @Test func bitRateClampedToMaximum() {
        var options = AudioFormatConverterOptions()
        options.bitRate = 1_000_000
        #expect(options.bitRate == AudioFormatConverterOptions.bitRateRange.upperBound)
    }

    @Test func bitRateDefaultIs256k() {
        let options = AudioFormatConverterOptions()
        #expect(options.bitRate == 256_000)
    }

    @Test func formatAcceptsSupportedTypes() {
        let supported: [AudioFileType] = [.wav, .aiff, .caf, .m4a, .mp3]
        for type in supported {
            var options = AudioFormatConverterOptions()
            options.format = type
            #expect(options.format == type)
        }
    }

    // MARK: - init(url:)

    @Test func initFromURL() {
        let url = TestBundleResources.shared.tabla_wav
        let options = AudioFormatConverterOptions(url: url)
        #expect(options != nil)
        #expect(options?.format == .wav)
        #expect(options?.sampleRate != nil)
        #expect(options?.bitsPerChannel != nil)
        #expect(options?.channels != nil)
    }

    @Test func initFromURLReturnsNilForInvalidURL() {
        let url = URL(fileURLWithPath: "/nonexistent/file.wav")
        let options = AudioFormatConverterOptions(url: url)
        #expect(options == nil)
    }

    // MARK: - init(pcmFormat:)

    @Test func initPCMFormatRejectsCompressed() {
        #expect(throws: Error.self) {
            _ = try AudioFormatConverterOptions(pcmFormat: .m4a)
        }
    }

    @Test func initPCMFormatAcceptsPCM() throws {
        let options = try AudioFormatConverterOptions(
            pcmFormat: .wav,
            sampleRate: 44100,
            bitsPerChannel: 24,
            channels: 2
        )
        #expect(options.format == .wav)
        #expect(options.sampleRate == 44100)
        #expect(options.bitsPerChannel == 24)
        #expect(options.channels == 2)
    }

    // MARK: - BitDepthRule

    @Test func bitDepthRuleDefaultIsAny() {
        let options = AudioFormatConverterOptions()
        #expect(options.bitDepthRule == .any)
    }

    @Test func bitDepthRuleLessThanOrEqualBlocksUpsampling() {
        let inputDescription = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: 0,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = 24
        options.bitDepthRule = .lessThanOrEqual

        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: inputDescription
        )

        // Should not upsample from 16 to 24
        #expect(output.mBitsPerChannel == 16)
    }

    @Test func bitDepthRuleAnyAllowsUpsampling() {
        let inputDescription = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: 0,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = 24
        options.bitDepthRule = .any

        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: inputDescription
        )

        #expect(output.mBitsPerChannel == 24)
    }

    // MARK: - eraseFile default

    @Test func eraseFileDefaultIsTrue() {
        let options = AudioFormatConverterOptions()
        #expect(options.conflictScheme == .overwrite)
    }

    // MARK: - init(format:)

    @Test func initWithFormatSetsFormatOnly() {
        let options = AudioFormatConverterOptions(format: .m4a)
        #expect(options.format == .m4a)
        #expect(options.sampleRate == nil)
        #expect(options.bitsPerChannel == nil)
        #expect(options.channels == nil)
        #expect(options.bitDepthRule == .any)
    }

    // MARK: - init(audioFile:)

    @Test func initFromAudioFile() throws {
        let url = TestBundleResources.shared.tabla_wav
        let audioFile = try AVAudioFile(forReading: url)
        let options = AudioFormatConverterOptions(audioFile: audioFile)

        #expect(options != nil)
        #expect(options?.format == .wav)
        #expect(options?.sampleRate ?? 0 > 0)
        #expect(options?.channels ?? 0 > 0)
    }

    // MARK: - Serializable round-trip

    @Test func serializableRoundTrip() throws {
        var original = AudioFormatConverterOptions()
        original.format = .wav
        original.sampleRate = 48000
        original.bitsPerChannel = 24
        original.channels = 2
        original.bitRate = 128_000
        original.bitDepthRule = .lessThanOrEqual
        original.conflictScheme = .error

        let data = try #require(original.dataRepresentation)
        let decoded = try AudioFormatConverterOptions(data: data)

        #expect(decoded.format == .wav)
        #expect(decoded.sampleRate == 48000)
        #expect(decoded.bitsPerChannel == 24)
        #expect(decoded.channels == 2)
        #expect(decoded.bitRate == 128_000)
        #expect(decoded.bitDepthRule == .lessThanOrEqual)
        #expect(decoded.conflictScheme == .error)
    }

    @Test func serializableRoundTripWithNilValues() throws {
        let original = AudioFormatConverterOptions()

        let data = try #require(original.dataRepresentation)
        let decoded = try AudioFormatConverterOptions(data: data)

        #expect(decoded.format == nil)
        #expect(decoded.sampleRate == nil)
        #expect(decoded.bitsPerChannel == nil)
        #expect(decoded.channels == nil)
        #expect(decoded.bitRate == 256_000)
        #expect(decoded.bitDepthRule == .any)
        #expect(decoded.conflictScheme == .overwrite)
    }

    // MARK: - channels property

    @Test func channelsNilByDefault() {
        let options = AudioFormatConverterOptions()
        #expect(options.channels == nil)
    }

    // MARK: - isInterleaved property

    @Test func isInterleavedNilByDefault() {
        let options = AudioFormatConverterOptions()
        #expect(options.isInterleaved == nil)
    }
}
