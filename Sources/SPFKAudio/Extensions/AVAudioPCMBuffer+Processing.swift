// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFoundation
import Foundation
import SPFKUtils

extension AVAudioPCMBuffer {
    /// Read the contents of the url into this buffer
    public convenience init?(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        try self.init(file: file)
    }

    /// Read entire file and return a new AVAudioPCMBuffer with its contents
    public convenience init?(file: AVAudioFile) throws {
        file.framePosition = 0

        self.init(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )

        try file.read(into: self)
    }
}

extension AVAudioPCMBuffer {
    /// Find peak in the buffer
    /// - Returns: A Peak struct containing the time, frame position and peak amplitude
    public func peak() -> Peak? {
        guard frameLength > 0 else { return nil }
        guard let floatData = floatChannelData else { return nil }

        var value = Peak()
        var position = 0
        var peakValue: Float = Peak.min
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
                    value.time = Double(position) / Double(format.sampleRate)
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
        var peak: Float = Peak.min

        for i in 0 ..< buffer.count {
            // store the absolute value of the sample
            let absSample = abs(buffer[i])
            peak = max(peak, absSample)
        }
        return peak
    }

    /// - Returns: A normalized buffer
    public func normalize() -> AVAudioPCMBuffer? {
        guard let floatData = floatChannelData else { return self }

        let normalizedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        )

        let length: AVAudioFrameCount = frameLength
        let channelCount = Int(format.channelCount)

        guard let peak: Peak = peak() else {
            Log.error("Failed getting peak amplitude, returning original buffer")
            return self
        }

        let gainFactor: Float = 1 / peak.amplitude

        // i is the index in the buffer
        for i in 0 ..< Int(length) {
            // n is the channel
            for n in 0 ..< channelCount {
                let sample = floatData[n][i] * gainFactor
                normalizedBuffer?.floatChannelData?[n][i] = sample
            }
        }

        normalizedBuffer?.frameLength = length

        return normalizedBuffer
    }

    /// - Returns: A reversed buffer
    public func reverse() -> AVAudioPCMBuffer? {
        guard let reversedBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        ) else { return nil }

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
    ///   - linearRamp: use a linear ramp, will be exponential by default
    /// - Returns: A new buffer from this one that has fades applied to it
    public func fade(
        inTime: TimeInterval = 0,
        outTime: TimeInterval = 0,
        linearRamp: Bool = false
    ) -> AVAudioPCMBuffer? {
        guard inTime > 0 || outTime > 0 else {
            Log.error("Error fading buffer, inTime or outTime must be > 0")
            return nil
        }

        guard let floatChannelData else {
            Log.error("floatChannelData is nil")
            return nil
        }

        let fadeBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCapacity
        )

        let length: UInt32 = frameLength
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        // initial starting point for the gain, if there is a fade in, start it at .01 otherwise at 1
        var gain: Double = inTime > 0 ? 0.01 : 1

        let sampleTime: Double = 1.0 / sampleRate

        var fadeInPower: Double = 1
        var fadeOutPower: Double = 1

        if linearRamp {
            gain = inTime > 0 ? 0 : 1
            fadeInPower = sampleTime / inTime

        } else {
            fadeInPower = exp(log(10) * sampleTime / inTime)
        }

        if linearRamp {
            fadeOutPower = sampleTime / outTime

        } else {
            fadeOutPower = exp(-log(25) * sampleTime / outTime)
        }

        // where in the buffer to end the fade in
        let fadeInSamples = Int(sampleRate * inTime)
        // where in the buffer to start the fade out
        let fadeOutSamples = Int(Double(length) - (sampleRate * outTime))

        // i is the index in the buffer
        for i in 0 ..< Int(length) {
            // n is the channel
            for n in 0 ..< channelCount {
                if i < fadeInSamples, inTime > 0 {
                    if linearRamp {
                        gain *= fadeInPower
                    } else {
                        gain += fadeInPower
                    }

                } else if i > fadeOutSamples, outTime > 0 {
                    if linearRamp {
                        gain -= fadeOutPower
                    } else {
                        gain *= fadeOutPower
                    }
                } else {
                    gain = 1.0
                }

                // sanity check
                gain = gain.clamped(to: 0 ... 1)

                let adjustedSample = floatChannelData[n][i] * Float(gain)

                fadeBuffer?.floatChannelData?[n][i] = adjustedSample
            }
        }

        // update this
        fadeBuffer?.frameLength = length

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

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: convertToFormat,
                                               frameCapacity: AVAudioFrameCount(newFrameCapacity)) else {
            throw NSError(description: "Failed to create buffer with format \(convertToFormat.readableDescription)")
        }

        Log.debug("Creating buffer with format", convertToFormat, "frameCapacity", newFrameCapacity)

        var error: NSError?
        let status: AVAudioConverterOutputStatus = converter.convert(to: outBuffer,
                                                                     error: &error,
                                                                     withInputFrom: inputBlock)
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

    /// Write this buffer with it's current format to file
    /// - Parameter url: URL to write to
    public func write(to url: URL) throws {
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false

        let output = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        try output.write(from: self)
    }
}
