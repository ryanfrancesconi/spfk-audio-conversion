// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKBase

public struct WriteableFileProperties: Sendable {
    /// The url being written to, persists after close
    public let url: URL

    /// The file format being written
    public let fileFormat: AVAudioFormat

    /// The channel of the audio device this is reading from
    public let channel: UInt32

    /// Timestamp when the first samples appear in the process block during writing
    public var timestamp: AVAudioTime?

    /// Total current duration of the file, will increment while writing
    public private(set) var duration: TimeInterval = 0

    /// Should be set the amount of latency samples in the input device
    public let ioLatency: AVAudioFrameCount

    /// The total samples read from the input stream
    public var totalFramesRead: AVAudioFrameCount = 0

    /// The actual amount of samples written to file. In the case of using
    /// calculated hardware latency, this would be less than the samples read
    /// from the tap
    public var totalFramesWritten: AVAudioFramePosition = 0 {
        didSet {
            duration = Double(totalFramesWritten) / fileFormat.sampleRate

            // for displaying a temporary in progress waveform
            amplitudeArray.append(currentAmplitude)

            // Log.debug("Recorded \(duration) seconds...")
        }
    }

    /// Current amplitude being written represented as RMS. Suitable for use with a VU meter
    public var currentAmplitude: Float = 0

    /// An array of amplitude values used to create a temporary waveform for display
    /// while recording is progressing
    public private(set) var amplitudeArray = [Float]()

    public init(
        url: URL,
        fileFormat: AVAudioFormat,
        channel: UInt32,
        timestamp: AVAudioTime? = nil,
        duration: TimeInterval,
        ioLatency: AVAudioFrameCount = 0,
        totalFramesRead: AVAudioFrameCount = 0,
        totalFramesWritten: AVAudioFramePosition = 0,
    ) {
        self.url = url
        self.fileFormat = fileFormat
        self.channel = channel
        self.timestamp = timestamp
        self.duration = duration
        self.ioLatency = ioLatency
        self.totalFramesRead = totalFramesRead
        self.totalFramesWritten = totalFramesWritten
    }

    func checkLatency(buffer: inout AVAudioPCMBuffer) throws -> Bool {
        // Latency is longer than bufferSize so wait till next iterations
        guard totalFramesRead > ioLatency else { return false }

        let latencyOffset: AVAudioFrameCount = totalFramesRead - ioLatency

        let startSample = buffer.frameLength - latencyOffset

        // edit the first buffer to remove io latency samples length
        if buffer.frameLength > latencyOffset,
            let offsetBuffer = try buffer.copyFrom(startSample: startSample)
        {
            buffer = offsetBuffer
        }

        return true
    }
}
