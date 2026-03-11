// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioBase
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct CreateOutputDescriptionTests {
    /// Reusable 44.1kHz stereo 24-bit input description
    private var stereo24bit: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger,
            mBytesPerPacket: 6,
            mFramesPerPacket: 1,
            mBytesPerFrame: 6,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 24,
            mReserved: 0
        )
    }

    // MARK: - Sample rate and channel passthrough

    @Test func nilOptionsAdoptInputValues() {
        let options = AudioFormatConverterOptions()
        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: stereo24bit
        )

        #expect(output.mSampleRate == 44100)
        #expect(output.mChannelsPerFrame == 2)
        #expect(output.mBitsPerChannel == 24)
    }

    @Test func optionsOverrideInputValues() {
        var options = AudioFormatConverterOptions()
        options.sampleRate = 48000
        options.channels = 1
        options.bitsPerChannel = 16

        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: stereo24bit
        )

        #expect(output.mSampleRate == 48000)
        #expect(output.mChannelsPerFrame == 1)
        #expect(output.mBitsPerChannel == 16)
    }

    // MARK: - Format flags

    @Test func aiffSetsBigEndianFlag() {
        let options = AudioFormatConverterOptions()
        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileAIFFType,
            inputDescription: stereo24bit
        )

        #expect(output.mFormatFlags & kLinearPCMFormatFlagIsBigEndian != 0)
    }

    @Test func wavDoesNotSetBigEndianFlag() {
        let options = AudioFormatConverterOptions()
        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: stereo24bit
        )

        #expect(output.mFormatFlags & kLinearPCMFormatFlagIsBigEndian == 0)
    }

    @Test func wav8BitRemovesSignedIntegerFlag() {
        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = nil

        // Create an 8-bit input
        var input8bit = stereo24bit
        input8bit.mBitsPerChannel = 8
        input8bit.mBytesPerFrame = 2
        input8bit.mBytesPerPacket = 2

        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: input8bit
        )

        // 8-bit passthrough from input (Options clamping only applies to the setter, not createOutputDescription)
        #expect(output.mBitsPerChannel == 8)
        // 8-bit WAV should NOT have kAudioFormatFlagIsSignedInteger
        #expect(output.mFormatFlags & kAudioFormatFlagIsSignedInteger == 0)
    }

    // MARK: - Zero bit depth fallback

    @Test func zeroBitsPerChannelFallsBackTo16() {
        let options = AudioFormatConverterOptions()

        // Compressed input may report 0 bits per channel
        var compressedInput = stereo24bit
        compressedInput.mBitsPerChannel = 0
        compressedInput.mBytesPerFrame = 0
        compressedInput.mBytesPerPacket = 0

        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: compressedInput
        )

        #expect(output.mBitsPerChannel == 16)
        #expect(output.mBytesPerFrame == 4) // 16bit * 2ch / 8
        #expect(output.mBytesPerPacket == 4)
    }

    // MARK: - Bytes per frame calculation

    @Test func bytesPerFrameCalculatedCorrectly() {
        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = 24
        options.channels = 1

        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: stereo24bit
        )

        // 24 bits * 1 channel / 8 = 3 bytes per frame
        #expect(output.mBytesPerFrame == 3)
        #expect(output.mBytesPerPacket == 3)
        #expect(output.mFramesPerPacket == 1)
    }

    // MARK: - Format ID is always linear PCM

    @Test func outputFormatIDIsAlwaysLinearPCM() {
        let options = AudioFormatConverterOptions()
        let output = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileCAFType,
            inputDescription: stereo24bit
        )

        #expect(output.mFormatID == kAudioFormatLinearPCM)
    }
}
