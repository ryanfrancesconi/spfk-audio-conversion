// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct AudioFormatConverterBitDepthRuleTests {
    // MARK: - BitDepthRule

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

    // MARK: - isInterleaved property
}
