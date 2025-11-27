// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import OTAtomics
import SPFKBase
import SwiftExtensions

/// An inner class to represent one channel of data to record to file
public final class WriteableFile: CustomStringConvertible {
    /// Simple description of the file
    public var description: String {
        "WriteableFile(url: \(url.path), channel: \(channel))"
    }

    /// The url being written to, persists after close
    public let url: URL

    /// The file format being written
    public let fileFormat: AVAudioFormat

    /// The channel of the audio device this is reading from
    public let channel: UInt32

    /// This is the internal file
    public private(set) var file: AVAudioFile?

    /// Current amplitude being written represented as RMS. Suitable for use with a VU meter
    public private(set) var amplitude: Float = 0

    /// Total current duration of the file, will increment while writing
    public private(set) var duration: TimeInterval = 0

    /// An array of amplitude values used to create a temporary waveform for display
    /// while recording is progressing
    public private(set) var amplitudeArray = [Float]()

    /// Timestamp when the first samples appear in the process block during writing
    public private(set) var timestamp: AVAudioTime?

    /// Should be set the amount of latency samples in the input device
    public let ioLatency: AVAudioFrameCount

    /// The total samples read from the input stream
    public private(set) var totalFramesRead: AVAudioFrameCount = 0

    /// The actual amount of samples written to file. In the case of using
    /// calculated hardware latency, this would be less than the samples read
    /// from the tap
    public private(set) var totalFramesWritten: AVAudioFramePosition = 0 {
        didSet {
            duration = Double(totalFramesWritten) / fileFormat.sampleRate
        }
    }

    private var ioLatencyHandled: Bool = false

    /// Create the file, passing in an optional hardware latency
    public init(
        url: URL,
        fileFormat: AVAudioFormat,
        channel: UInt32,
        ioLatency: AVAudioFrameCount = 0
    ) throws {
        self.url = url
        self.fileFormat = fileFormat
        self.channel = channel
        self.ioLatency = ioLatency
    }

    func createFile() {
        guard file == nil else { return }

        do {
            timestamp = nil
            file = try AVAudioFile(forWriting: url, settings: fileFormat.settings)

        } catch {
            Log.error(error)
        }
    }

    /// Handle incoming data from the tap
    public func process(buffer: AVAudioPCMBuffer, time: AVAudioTime, write: Bool) throws {
        if write {
            try _write(buffer: buffer, at: time)
        }

        amplitude = buffer.rmsValue
    }

    // The actual buffer length is unpredicatable if using a Tap. This isn't ideal.
    // The system will change the buffer size to whatever it wants to, which seems
    // strange that they let you set a buffer size in the first place. macOS is setting to
    // 4800 when at 48k, or sampleRate / 10. That's a big buffer.
    private func _write(buffer: AVAudioPCMBuffer, at time: AVAudioTime) throws {
        var buffer = buffer

        totalFramesRead += buffer.frameLength

        if timestamp == nil {
            timestamp = time
        }

        if !ioLatencyHandled, ioLatency > 0 {
            if totalFramesRead > ioLatency {
                let latencyOffset: AVAudioFrameCount = totalFramesRead - ioLatency
                let startSample = buffer.frameLength - latencyOffset

                // edit the first buffer to remove io latency samples length
                if buffer.frameLength > latencyOffset,
                   let offsetBuffer = try buffer.copyFrom(startSample: startSample)
                {
                    buffer = offsetBuffer
                }

                ioLatencyHandled = true

            } else {
                // Latency is longer than bufferSize so wait till next iterations
                return
            }
        }

        guard let file else { return }

        try file.write(from: buffer)

        amplitudeArray.append(
            amplitude //.normalized(from: Float.unitIntervalRange, taper: AudioTaper.default.value)
        )

        totalFramesWritten = file.length
    }

    /// Release the file ?
    public func close() {
        file = nil
        amplitudeArray.removeAll()
    }
}
