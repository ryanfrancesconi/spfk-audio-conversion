// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation

extension AVAudioFormat {
    public var commonFormatReadableDescription: String? {
        switch commonFormat {
        case .pcmFormatInt16:
            return "Signed 16-bit native-endian integer"
        case .pcmFormatInt32:
            return "Signed 32-bit native-endian integer"
        case .pcmFormatFloat32:
            return "Native-endian 32 bit floating point"
        case .pcmFormatFloat64:
            return "Native-endian 64 bit floating point"
        default:
            return nil
        }
    }

    public var channelCountReadableDescription: String {
        var out = "Stereo"
        if channelCount == 1 {
            out = "Mono"
        } else if channelCount > 2 {
            out = "\(channelCount) Channel"
        }
        return out
    }

    public var readableDescription: String {
        var out = "\(sampleRate) Hz, " + channelCountReadableDescription

        if let commonFormatReadableDescription = commonFormatReadableDescription {
            out += ", \(commonFormatReadableDescription)"
        }

        return out
    }

    public var bitsPerChannel: UInt32 {
        streamDescription.pointee.mBitsPerChannel
    }

    public static func createPCMFormat(
        bitsPerChannel: UInt32,
        channels: UInt32,
        sampleRate: Double
    ) -> AVAudioFormat? {
        let outputBytesPerFrame = bitsPerChannel * channels / 8
        let outputBytesPerPacket = outputBytesPerFrame
        let formatFlags = kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger

        var outDesc = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: formatFlags,
            mBytesPerPacket: outputBytesPerPacket,
            mFramesPerPacket: 1,
            mBytesPerFrame: outputBytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0
        )

        return AVAudioFormat(streamDescription: &outDesc)
    }
}
