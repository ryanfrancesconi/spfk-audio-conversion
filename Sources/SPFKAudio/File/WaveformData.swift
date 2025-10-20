// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

/// Data needed for drawing waveforms
public struct WaveformData: Equatable, Hashable, Serializable {
    public private(set) var floatChannelData: FloatChannelData
    public private(set) var samplesPerPoint: Int
    public private(set) var audioDuration: TimeInterval
    public private(set) var sampleRate: Double
    public private(set) var samplesPerSecond: Double

    public var channelCount: Int {
        floatChannelData.count
    }

    public init(
        floatChannelData: FloatChannelData = [[]],
        samplesPerPoint: Int = 0,
        audioDuration: TimeInterval = 0,
        sampleRate: Double = 0
    ) {
        self.floatChannelData = floatChannelData
        self.samplesPerPoint = samplesPerPoint
        self.audioDuration = audioDuration
        self.sampleRate = sampleRate
        self.samplesPerSecond = sampleRate / samplesPerPoint.double
    }

    /// Extract a time range of audio data
    /// - Parameter timeRange: time range to extract
    /// - Returns: FloatChannelData suitable for drawing
    public func subdata(in timeRange: ClosedRange<TimeInterval>) throws -> FloatChannelData {
        let startTime = timeRange.lowerBound.clamped(
            to: 0 ... audioDuration - 0.01
        )

        let endTime = timeRange.upperBound.clamped(
            to: startTime + 0.01 ... audioDuration
        )

        guard startTime < endTime else {
            throw NSError(description: "audioDuration: \(audioDuration), invalid edit times \(startTime)...\(endTime)")
        }

        let startIndex = Int(startTime * samplesPerSecond)
        let endIndex = Int(endTime * samplesPerSecond)
        let editedCount = (endIndex - startIndex)

        var subdata: FloatChannelData = newFloatChannelData(channelCount: channelCount, length: editedCount)

        var k = 0

        for i in startIndex ..< endIndex {
            for n in 0 ..< channelCount {
                subdata[n][k] = floatChannelData[n][i]
            }

            try Task.checkCancellation()

            k += 1
        }

        return subdata
    }
}
