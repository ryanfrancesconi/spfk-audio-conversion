// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Accelerate
import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKAudioConverterC
import SPFKBase

/// Decodes Ogg Vorbis and Ogg Opus through libsndfile, which neither `ExtAudioFile` nor
/// `AVAsset` opens.
///
/// `@unchecked Sendable` on the same terms as `MatroskaAudioDecoder`: it holds a position in a file,
/// so one consumer may drive it and no more.
public final class SndFilePCMSource: @unchecked Sendable {
    public let url: URL

    /// Deinterleaved 32-bit float at the file's own rate.
    public let processingFormat: AVAudioFormat

    public private(set) var framePosition: AVAudioFramePosition = 0

    private let reader: SndFileReader
    private var interleaved: [Float] = []

    public init(url: URL) throws {
        self.url = url
        reader = try SndFileReader(path: url.path)

        guard reader.channelCount > 0,
              let format = AVAudioFormat(
                  standardFormatWithSampleRate: reader.sampleRate,
                  channels: AVAudioChannelCount(reader.channelCount)
              )
        else {
            throw NSError(description: "\(url.lastPathComponent) has no audio channels")
        }

        processingFormat = format
    }
}

// MARK: - SeekablePCMSource

extension SndFilePCMSource: SeekablePCMSource {
    public var totalFrameCount: AVAudioFramePosition {
        max(0, reader.frameCount)
    }

    public func readNextChunk(into buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount) throws -> AVAudioFrameCount {
        let channelCount = Int(processingFormat.channelCount)
        let wanted = Int(min(frameCount, buffer.frameCapacity))

        guard wanted > 0, let channels = buffer.floatChannelData else {
            buffer.frameLength = 0
            return 0
        }

        if interleaved.count < wanted * channelCount {
            interleaved = [Float](repeating: 0, count: wanted * channelCount)
        }

        let read = interleaved.withUnsafeMutableBufferPointer { samples -> Int64 in
            guard let base = samples.baseAddress else { return -1 }
            return reader.read(base, frames: Int64(wanted))
        }

        guard read >= 0 else {
            throw NSError(description: "libsndfile failed to decode \(url.lastPathComponent)")
        }

        interleaved.withUnsafeBufferPointer { samples in
            guard let base = samples.baseAddress else { return }

            for channel in 0 ..< channelCount {
                vDSP_mmov(base + channel, channels[channel], 1, vDSP_Length(read), vDSP_Length(channelCount), 1)
            }
        }

        buffer.frameLength = AVAudioFrameCount(read)
        framePosition += AVAudioFramePosition(read)

        return AVAudioFrameCount(read)
    }

    public func seek(toFrame frame: AVAudioFramePosition) throws {
        guard reader.seek(toFrame: frame) else {
            throw NSError(description: "libsndfile could not seek \(url.lastPathComponent) to frame \(frame)")
        }

        framePosition = frame
    }
}
