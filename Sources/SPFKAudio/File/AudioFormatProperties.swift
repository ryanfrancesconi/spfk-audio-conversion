// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import OrderedCollections
import SPFKTime

public struct AudioFormatProperties: Hashable, Codable {
    public private(set) var channelCount: AVAudioChannelCount
    public private(set) var sampleRate: Double
    public private(set) var bitsPerChannel: Int?
    public private(set) var duration: TimeInterval = 0

    // MARK: cached descriptions for displaying in the UI

    public private(set) var durationDescription: String = ""
    public private(set) var formatDescription: String = ""
    public private(set) var channelsDescription: String = ""

    public var dictionary: OrderedDictionary<String, String> { [
        "Format": formatDescription,
        "Duration": durationDescription,
    ] }

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

        update()
    }

    public init(audioFile: AVAudioFile) {
        self.channelCount = audioFile.fileFormat.channelCount
        self.sampleRate = audioFile.fileFormat.sampleRate
        self.bitsPerChannel = audioFile.fileFormat.bitsPerChannel.int
        self.duration = audioFile.duration

        update()
    }

    private mutating func update() {
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

        var out = "\(kHzString) kHz, "

        if let bitsPerChannel {
            out += bitsPerChannel > 0 ? "\(bitsPerChannel) bit " : ""
        }

        if channelsDescription != "" {
            out += "\(channelsDescription)"
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
