// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import SPFKUtils
import AVFoundation
import CryptoKit

extension AVAudioPCMBuffer {
    /// Hash useful for testing
    public var md5: String {
        var sampleData = Data()

        if let floatChannelData {
            for frame in 0 ..< frameCapacity {
                for channel in 0 ..< format.channelCount {
                    let sample = floatChannelData[Int(channel)][Int(frame)]

                    withUnsafePointer(to: sample) { ptr in
                        sampleData.append(UnsafeBufferPointer(start: ptr, count: 1))
                    }
                }
            }
        }

        let digest = Insecure.MD5.hash(data: sampleData)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    public var isSilent: Bool {
        if let floatChannelData = floatChannelData {
            for channel in 0 ..< format.channelCount {
                for frame in 0 ..< frameLength {
                    if floatChannelData[Int(channel)][Int(frame)] != 0.0 {
                        return false
                    }
                }
            }
        }
        return true
    }

    /// Add to an existing buffer
    ///
    /// - Parameter buffer: Buffer to append
    public func append(_ buffer: AVAudioPCMBuffer) throws {
        try append(buffer, startingFrame: 0, frameCount: buffer.frameLength)
    }

    /// Add to an existing buffer with specific starting frame and size
    /// - Parameters:
    ///   - buffer: Buffer to append
    ///   - startingFrame: Starting frame location
    ///   - frameCount: Number of frames to append
    public func append(_ buffer: AVAudioPCMBuffer,
                       startingFrame: AVAudioFramePosition,
                       frameCount: AVAudioFrameCount) throws {
        // -
        guard format == buffer.format else {
            throw NSError(description: "Format mismatch")
        }

        guard startingFrame + AVAudioFramePosition(frameCount) <= AVAudioFramePosition(buffer.frameLength) else {
            throw NSError(description: "Insufficient audio in buffer")
        }

        guard frameLength + frameCount <= frameCapacity else {
            throw NSError(description: "Insufficient space in buffer")
        }

        guard let dst1 = floatChannelData?[0],
              let src1 = buffer.floatChannelData?[0],
              let dst2 = floatChannelData?[1],
              let src2 = buffer.floatChannelData?[1] else {
            throw NSError(description: "Buffer data is invalid")
        }

        memcpy(
            dst1.advanced(by: stride * Int(frameLength)),
            src1.advanced(by: stride * Int(startingFrame)),
            Int(frameCount) * stride * MemoryLayout<Float>.size
        )

        memcpy(
            dst2.advanced(by: stride * Int(frameLength)),
            src2.advanced(by: stride * Int(startingFrame)),
            Int(frameCount) * stride * MemoryLayout<Float>.size
        )

        frameLength += frameCount
    }

    /// Copies data from another PCM buffer.  Will copy to the end of the buffer (frameLength), and
    /// increment frameLength. Will not exceed frameCapacity.
    ///
    /// - Parameter buffer: The source buffer that data will be copied from.
    /// - Parameter readOffset: The offset into the source buffer to read from.
    /// - Parameter frames: The number of frames to copy from the source buffer.
    /// - Returns: The number of frames copied.
    @discardableResult public func copy(
        from buffer: AVAudioPCMBuffer,
        readOffset: AVAudioFrameCount = 0,
        frames: AVAudioFrameCount = 0
    ) throws -> AVAudioFrameCount {
        // -
        let remainingCapacity = frameCapacity - frameLength

        guard remainingCapacity > 0 else {
            throw NSError(description: "AVAudioBuffer copy(from) - no capacity!")
        }

        guard format == buffer.format else {
            throw NSError(description: "AVAudioBuffer copy(from) - formats must match!")
        }

        let totalFrames = Int(
            min(
                min(frames == 0 ? buffer.frameLength : frames, remainingCapacity),
                buffer.frameLength - readOffset
            )
        )

        guard totalFrames > 0 else {
            throw NSError(description: "AVAudioBuffer copy(from) - No frames to copy!")
        }

        let frameSize = Int(format.streamDescription.pointee.mBytesPerFrame)

        if let src = buffer.floatChannelData,
           let dst = floatChannelData {
            for channel in 0 ..< Int(format.channelCount) {
                memcpy(dst[channel] + Int(frameLength), src[channel] + Int(readOffset), totalFrames * frameSize)
            }
        } else if let src = buffer.int16ChannelData,
                  let dst = int16ChannelData {
            for channel in 0 ..< Int(format.channelCount) {
                memcpy(dst[channel] + Int(frameLength), src[channel] + Int(readOffset), totalFrames * frameSize)
            }
        } else if let src = buffer.int32ChannelData,
                  let dst = int32ChannelData {
            for channel in 0 ..< Int(format.channelCount) {
                memcpy(dst[channel] + Int(frameLength), src[channel] + Int(readOffset), totalFrames * frameSize)
            }
        } else {
            return 0
        }

        frameLength += AVAudioFrameCount(totalFrames)

        return AVAudioFrameCount(totalFrames)
    }

    /// Copy from a certain point tp the end of the buffer
    /// - Parameter startSample: Point to start copy from
    /// - Returns: an AVAudioPCMBuffer copied from a sample offset to the end of the buffer.
    public func copyFrom(startSample: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard startSample < frameLength,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength - startSample) else {
            return nil
        }
        let framesCopied = try buffer.copy(from: self, readOffset: startSample)
        return framesCopied > 0 ? buffer : nil
    }

    /// Copy from the beginner of a buffer to a certain number of frames
    /// - Parameter count: Length of frames to copy
    /// - Returns: an AVAudioPCMBuffer copied from the start of the buffer to the specified endSample.
    public func copyTo(count: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
            return nil
        }
        let framesCopied = try buffer.copy(from: self, readOffset: 0, frames: min(count, frameLength))
        return framesCopied > 0 ? buffer : nil
    }

    /// Extract a portion of the buffer
    ///
    /// - Parameter startTime: The time of the in point of the extraction
    /// - Parameter endTime: The time of the out point
    /// - Returns: A new edited AVAudioPCMBuffer
    public func extract(from startTime: TimeInterval,
                        to endTime: TimeInterval) throws -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let startSample = AVAudioFrameCount(startTime * sampleRate)
        var endSample = AVAudioFrameCount(endTime * sampleRate)

        if endSample == 0 {
            endSample = frameLength
        }

        let frameCapacity = endSample - startSample

        guard frameCapacity > 0 else {
            throw NSError(description: "startSample must be before endSample")
        }

        guard let editedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw NSError(description: "Failed to create edited buffer")
        }

        guard try editedBuffer.copy(from: self, readOffset: startSample, frames: frameCapacity) > 0 else {
            throw NSError(description: "Failed to write to edited buffer")
        }

        return editedBuffer
    }

    /// Copy the contents of this buffer into a new buffer `numberOfDuplicates` amounts
    public func loop(numberOfDuplicates: Int) throws -> AVAudioPCMBuffer {
        guard let duplicatedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity * AVAudioFrameCount(numberOfDuplicates)
        ) else {
            throw NSError(description: "Failed to create new buffer")
        }

        for _ in 0 ..< numberOfDuplicates {
            try duplicatedBuffer.copy(from: self)
        }

        return duplicatedBuffer
    }
}
