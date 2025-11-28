// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase
import SwiftExtensions

/// An inner class to represent one channel of data to record to file
public final class WriteableFile {
    /// Simple description of the file
    public var description: String {
        String(describing: properties)
    }

    /// This is the internal file
    public private(set) var file: AVAudioFile?

    private var ioLatencyHandled: Bool = false

    public private(set) var properties: WriteableFileProperties

    /// Create the file, passing in an optional hardware latency
    public init(
        url: URL,
        fileFormat: AVAudioFormat,
        channel: UInt32,
        ioLatency: AVAudioFrameCount = 0,
    ) throws {
        properties = WriteableFileProperties(
            url: url,
            fileFormat: fileFormat,
            channel: channel,
            duration: 0,
            ioLatency: ioLatency,
        )
    }

    func open() throws {
        guard file == nil else {
            assertionFailure()
            return
        }

        properties.timestamp = nil

        file = try AVAudioFile(
            forWriting: properties.url,
            settings: properties.fileFormat.settings,
        )
    }

    /// Handle incoming data from the tap
    public func process(
        buffer: AVAudioPCMBuffer,
        time: AVAudioTime,
        write: Bool,
    ) throws {
        if write {
            try _write(buffer: buffer, at: time)
        }

        properties.currentAmplitude = buffer.rmsValue
    }

    // The system will change the buffer size to whatever it wants to, which seems
    // strange that they let you set a buffer size in the first place. macOS is setting to
    // 4800 when at 48k
    private func _write(buffer: AVAudioPCMBuffer, at time: AVAudioTime) throws {
        guard let file else {
            assertionFailure()
            return
        }

        if #available(macOS 15, *) {
            guard file.isOpen else {
                assertionFailure()
                return
            }
        }

        var buffer = buffer

        properties.totalFramesRead += buffer.frameLength

        if properties.timestamp == nil {
            properties.timestamp = time
        }

        if !ioLatencyHandled, properties.ioLatency > 0 {
            if try properties.checkLatency(buffer: &buffer) {
                ioLatencyHandled = true

            } else {
                // Latency is longer than bufferSize so wait till next iterations
                return
            }
        }

        try file.write(from: buffer)

        properties.totalFramesWritten = file.length
    }

    /// Release the file ?
    public func close() {
        file = nil
    }
}
