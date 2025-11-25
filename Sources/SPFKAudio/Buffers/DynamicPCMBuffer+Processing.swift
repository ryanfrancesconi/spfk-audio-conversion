// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

extension DynamicPCMBuffer {
    /// - Returns: A normalized buffer
    public func normalize() throws -> AVAudioPCMBuffer {
        try internalBuffer.normalize()
    }

    /// - Returns: A reversed buffer
    public func reverse() -> AVAudioPCMBuffer? {
        let reversedBuffer = AVAudioPCMBuffer(pcmFormat: internalBuffer.format,
                                              frameCapacity: internalBuffer.frameCapacity)

        var j = 0
        let length: AVAudioFrameCount = internalBuffer.frameLength
        let channelCount = Int(internalBuffer.format.channelCount)

        // i represents the normal buffer read in reverse
        for i in (0 ..< Int(length)).reversed() {
            // n is the channel
            for n in 0 ..< channelCount {
                // we write the reverseBuffer via the j index
                reversedBuffer?.floatChannelData?[n][j] = internalBuffer.floatChannelData?[n][i] ?? 0.0
            }
            j += 1
        }
        reversedBuffer?.frameLength = length
        return reversedBuffer
    }

    /// - Returns: A new buffer from this one that has fades applied to it. Pass 0 for either parameter
    /// if you only want one of them. The ramp is exponential by default.
    public func fade(inTime: Double,
                     outTime: Double,
                     linearRamp: Bool = false) -> AVAudioPCMBuffer?
    {
        guard let floatData = internalBuffer.floatChannelData, inTime > 0 || outTime > 0 else {
            Log.error("Error fading buffer")
            return nil
        }

        let fadeBuffer = AVAudioPCMBuffer(pcmFormat: internalBuffer.format,
                                          frameCapacity: internalBuffer.frameCapacity)

        let length: UInt32 = internalBuffer.frameLength
        let sampleRate = internalBuffer.format.sampleRate
        let channelCount = Int(internalBuffer.format.channelCount)

        // initial starting point for the gain, if there is a fade in, start it at .01 otherwise at 1
        var gain: Double = inTime > 0 ? 0.01 : 1

        let sampleTime = 1.0 / sampleRate

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
                if gain > 1 {
                    gain = 1
                } else if gain < 0 {
                    gain = 0
                }

                let sample = floatData[n][i] * Float(gain)
                fadeBuffer?.floatChannelData?[n][i] = sample
            }
        }
        // update this
        fadeBuffer?.frameLength = length

        // set the buffer now to be the faded one
        return fadeBuffer
    }
}
