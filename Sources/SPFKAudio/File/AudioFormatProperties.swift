// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKMetadata

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
}
