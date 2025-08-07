// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation

public struct AudioFormatProperties: Hashable, Codable {
    public var channelCount: AVAudioChannelCount

    public var sampleRate: Double

    public var bitsPerChannel: Int?

    public var duration: TimeInterval = 0

    public var formatDescription: String {
        var out = "\(Int(sampleRate)), "

        if let bitsPerChannel {
            out += bitsPerChannel > 0 ? "\(bitsPerChannel) bit " : ""
        }

        if let channelsDescription {
            out += "\(channelsDescription)"
        }

        return out
    }

    public var channelsDescription: String? {
        guard channelCount > 0 else { return nil }

        var out = "Stereo"

        if channelCount == 1 {
            out = "Mono"

        } else if channelCount > 2 {
            out = "\(channelCount) Channel"
        }
        return out
    }

    public init(
        channelCount: AVAudioChannelCount,
        sampleRate: Double,
        bitsPerChannel: Int? = nil,
        duration: TimeInterval
    ) {
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.bitsPerChannel = bitsPerChannel
        self.duration = duration
    }

    public init(avAudioFile: AVAudioFile) {
        self.channelCount = avAudioFile.fileFormat.channelCount
        self.sampleRate = avAudioFile.fileFormat.sampleRate
        self.bitsPerChannel = avAudioFile.fileFormat.bitsPerChannel.int
        self.duration = avAudioFile.duration
    }
}
