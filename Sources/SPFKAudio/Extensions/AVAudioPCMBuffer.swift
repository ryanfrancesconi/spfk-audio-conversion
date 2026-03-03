// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

@preconcurrency import AVFoundation
import Accelerate
import Foundation
import SPFKBase

extension AVAudioPCMBuffer {
    /// Find peak in the buffer
    /// - Returns: A Peak struct containing the time, frame position and peak amplitude
    public func peak() throws -> BufferPeak {
        guard frameLength > 0 else {
            throw NSError(description: "buffer is empty")
        }

        guard let floatData = floatChannelData else {
            throw NSError(description: "Failed to create floatChannelData")
        }

        var value = BufferPeak()
        var position = 0
        var peakValue: Float = BufferPeak.min
        let chunkLength = 512
        let channelCount = Int(format.channelCount)

        while true {
            if position + chunkLength >= frameLength {
                break
            }

            for channel in 0 ..< channelCount {
                var block = Array(repeating: Float(0), count: chunkLength)

                // fill the block with frameLength samples
                for i in 0 ..< block.count {
                    if i + position >= frameLength {
                        break
                    }

                    block[i] = floatData[channel][i + position]
                }

                // scan the block
                let blockPeak = getPeakAmplitude(from: block)

                if blockPeak > peakValue {
                    value.framePosition = position
                    value.sampleRate = format.sampleRate

                    peakValue = blockPeak
                }

                position += block.count
            }
        }

        value.amplitude = peakValue
        return value
    }

    // Returns the highest level in the given array
    private func getPeakAmplitude(from buffer: [Float]) -> Float {
        // create variable with very small value to hold the peak value
        var peak: Float = BufferPeak.min

        for i in 0 ..< buffer.count {
            // store the absolute value of the sample
            let absSample = abs(buffer[i])
            peak = max(peak, absSample)
        }
        return peak
    }

    /// - Returns: A normalized buffer
    public func normalize() throws -> AVAudioPCMBuffer {
        guard let floatData = floatChannelData else {
            throw NSError(description: "Failed to create floatChannelData")
        }

        guard
            let normalizedBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCapacity
            )
        else {
            throw NSError(description: "Failed to create buffer")
        }

        let length: AVAudioFrameCount = frameLength
        let channelCount = Int(format.channelCount)

        let peak: BufferPeak = try peak()

        let gainFactor: Float = 1 / peak.amplitude

        // i is the index in the buffer
        for i in 0 ..< Int(length) {
            // n is the channel
            for n in 0 ..< channelCount {
                let sample = floatData[n][i] * gainFactor
                normalizedBuffer.floatChannelData?[n][i] = sample
            }
        }

        normalizedBuffer.frameLength = length

        return normalizedBuffer
    }

    /// - Returns: A reversed buffer
    public func reverse() throws -> AVAudioPCMBuffer {
        guard
            let reversedBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCapacity
            )
        else {
            throw NSError(description: "Failed to create buffer")
        }

        var j: Int = 0
        let length: AVAudioFrameCount = frameLength
        let channelCount = Int(format.channelCount)

        // i represents the normal buffer read in reverse
        for i in (0 ..< Int(length)).reversed() {
            // n is the channel
            for n in 0 ..< channelCount {
                // we write the reverseBuffer via the j index
                reversedBuffer.floatChannelData?[n][j] = floatChannelData?[n][i] ?? 0.0
            }

            j += 1
        }

        reversedBuffer.frameLength = length

        return reversedBuffer
    }

    /// Fade this buffer
    /// - Parameters:
    ///   - inTime: Fade In time
    ///   - outTime: Fade Out time
    /// - Returns: A new buffer from this one that has fades applied to it
    public func fade(
        inTime: TimeInterval = 0,
        outTime: TimeInterval = 0
    ) throws -> AVAudioPCMBuffer {
        guard inTime > 0 || outTime > 0 else {
            throw NSError(description: "Error fading buffer, inTime or outTime must be > 0")
        }

        guard let floatChannelData else {
            throw NSError(description: "floatChannelData is nil")
        }

        guard
            let fadeBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCapacity
            )
        else {
            throw NSError(description: "Failed to create buffer")
        }

        let length: UInt32 = frameLength
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        // initial starting point for the gain, if there is a fade in, start it at .01 otherwise at 1
        var gain: Double = inTime > 0 ? 0.01 : 1

        let sampleTime: Double = 1.0 / sampleRate
        let fadeInPower: Double = exp(log(10) * sampleTime / inTime)
        let fadeOutPower: Double = exp(-log(25) * sampleTime / outTime)

        // where in the buffer to end the fade in
        let fadeInSamples = Int(sampleRate * inTime)

        // where in the buffer to start the fade out
        let fadeOutSamples = Int(Double(length) - (sampleRate * outTime))

        // i is the index in the buffer
        for i in 0 ..< Int(length) {
            // n is the channel
            for n in 0 ..< channelCount {
                if i < fadeInSamples, inTime > 0 {
                    gain *= fadeInPower

                } else if i > fadeOutSamples, outTime > 0 {
                    gain *= fadeOutPower

                } else {
                    gain = 1.0
                }

                // sanity check
                gain = gain.clamped(to: Double.unitIntervalRange)

                let adjustedSample = floatChannelData[n][i] * Float(gain)

                fadeBuffer.floatChannelData?[n][i] = adjustedSample
            }
        }

        // update this
        fadeBuffer.frameLength = length

        // set the buffer now to be the faded one
        return fadeBuffer
    }

    /// Convert this buffer to a new format
    /// - Parameter convertToFormat: The destination format
    /// - Returns: A new `AVAudioPCMBuffer`
    public func convert(to convertToFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: format, to: convertToFormat) else {
            throw NSError(description: "Failed to create converter")
        }

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = AVAudioConverterInputStatus.haveData
            return self
        }

        // the frame capacity will be different if the sample rate is different
        let newFrameCapacity = (convertToFormat.sampleRate / format.sampleRate) * frameCapacity.double

        guard
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: convertToFormat,
                frameCapacity: AVAudioFrameCount(newFrameCapacity))
        else {
            throw NSError(description: "Failed to create buffer with format \(convertToFormat.readableDescription)")
        }

        Log.debug("Creating buffer with format", convertToFormat, "frameCapacity", newFrameCapacity)

        var error: NSError?
        let status: AVAudioConverterOutputStatus = converter.convert(
            to: outBuffer,
            error: &error,
            withInputFrom: inputBlock
        )
        switch status {
        case .haveData:
            /// All of the requested data was returned.
            return outBuffer

        case .inputRanDry:
            /// contains as much as could be converted.
            Log.error("inputRanDry")
            return outBuffer

        case .endOfStream:
            /// The end of stream has been reached. No data was returned.
            throw NSError(description: "endOfStream")

        case .error:
            /// An error occurred.
            throw error ?? NSError(description: "Unknown error")

        @unknown default:
            throw NSError(description: "Unknown status returned")
        }
    }
}
