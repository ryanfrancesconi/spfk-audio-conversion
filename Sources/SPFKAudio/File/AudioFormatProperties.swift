// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKTime

public struct AudioFormatProperties: Hashable, Sendable {
    public private(set) var channelCount: AVAudioChannelCount
    public private(set) var sampleRate: Double
    public private(set) var bitsPerChannel: Int?
    public private(set) var duration: TimeInterval = 0

    // MARK: Transients, cached descriptions for displaying in the UI

    public private(set) var durationDescription: String = ""
    public private(set) var formatDescription: String = ""
    public private(set) var channelsDescription: String = ""

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

        initialize()
    }

    public init(audioFile: AVAudioFile) {
        channelCount = audioFile.fileFormat.channelCount
        sampleRate = audioFile.fileFormat.sampleRate
        bitsPerChannel = audioFile.fileFormat.bitsPerChannel.int
        duration = audioFile.duration

        initialize()
    }

    private mutating func initialize() {
        updateChannelsDescription()
        updateFormatDescription()
        updateDurationDescription()
    }

    private mutating func updateChannelsDescription() {
        guard channelCount > 0 else {
            channelsDescription = ""
            return
        }

        var out = "Stereo"

        if channelCount == 1 {
            out = "Mono"

        } else if channelCount > 2 {
            out = "\(channelCount) Channel"
        }

        channelsDescription = out
    }

    private mutating func updateFormatDescription() {
        let kHz = (sampleRate / 1000).truncated(decimalPlaces: 1)
        var kHzString = kHz.string

        if kHz.truncatingRemainder(dividingBy: 1) == 0 {
            kHzString = kHz.int.string
        }

        var out = "\(kHzString) kHz"

        if let bitsPerChannel {
            out += bitsPerChannel > 0 ? ", \(bitsPerChannel) bit" : ""
        }

        if channelsDescription != "" {
            out += ", \(channelsDescription)"
        }

        formatDescription = out
    }

    private mutating func updateDurationDescription() {
        durationDescription = RealTimeDomain.string(
            seconds: duration,
            showHours: .auto,
            showMilliseconds: true
        )
    }
}

extension AudioFormatProperties: Codable {
    enum CodingKeys: String, CodingKey {
        case channelCount
        case sampleRate
        case bitsPerChannel
        case duration
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channelCount = try container.decode(AVAudioChannelCount.self, forKey: .channelCount)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        bitsPerChannel = try? container.decodeIfPresent(Int.self, forKey: .bitsPerChannel)
        duration = try container.decode(TimeInterval.self, forKey: .duration)

        initialize()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(channelCount, forKey: .channelCount)
        try container.encode(sampleRate, forKey: .sampleRate)
        try? container.encodeIfPresent(bitsPerChannel, forKey: .bitsPerChannel)
        try container.encode(duration, forKey: .duration)
    }
}
