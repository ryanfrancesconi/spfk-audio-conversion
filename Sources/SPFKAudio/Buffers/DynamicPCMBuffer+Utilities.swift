import AVFoundation
import Foundation
import SPFKUtils

extension DynamicPCMBuffer {
    public static func detectTransients(
        in buffer: AVAudioPCMBuffer,
        threshold: Float = -6,
        bufferDuration: TimeInterval = 0.01,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        progressHandler: ((ProgressValue1) -> Void)? = nil
    ) -> TransientCollection? {
        // -

        guard let floatData = buffer.floatChannelData else { return nil }

        var transients = [Transient]()
        let thresholdValue = threshold.clamped(to: Transient.dBRange)

        // 0 - 1
        var progressValue: Double = 0

        var position: Int = 0
        var endFrame: AVAudioFrameCount = buffer.frameLength

        let blockSize = Int(buffer.format.sampleRate * bufferDuration)

        if let startTime = startTime {
            position = max(0, Int(buffer.format.sampleRate * startTime))
        }

        if let endTime = endTime {
            endFrame = min(buffer.frameLength, AVAudioFrameCount(buffer.format.sampleRate * endTime))
        }

        guard position < endFrame else {
            Log.error("start frame must be less than end frame")
            return nil
        }

        Log.debug("Total Frames", Int(endFrame) - position, "blockSize", blockSize, "thresholdValue", thresholdValue)

        while true {
            if position + blockSize >= endFrame {
                // EOF
                Log.debug("EOF, position + blockSize >= endFrame. position:", position, "blockSize", blockSize, "endFrame", endFrame)
                break
            }

            for channel in 0 ..< buffer.format.channelCount {
                var block = Array(repeating: Float(0), count: blockSize)

                // fill the block with frameLength samples
                for i in 0 ..< block.count {
                    if i + position >= endFrame {
                        // EOF
                        Log.debug("EOF in block at", i + position, "EOF", endFrame)
                        break
                    }

                    block[i] = floatData[channel.int][i + position]
                }
                // scan the block
                let blockPeak = Self.getPeakAmplitude(from: block)

                // adjust to location of max amplitude in block
                let peakPosition = max(0, position - blockPeak.index)
                let time = Double(peakPosition) / Double(buffer.format.sampleRate)

                transients.append(
                    Transient(
                        time: time,
                        amplitude: blockPeak.amplitude,
                        position: AVAudioFramePosition(peakPosition),
                        passesThreshold: blockPeak.dBValue >= thresholdValue
                    )
                )

                position += blockSize

                progressValue = min(Double(position) / Double(endFrame), 1.0)
                progressHandler?(progressValue)
            }
        }

        return TransientCollection(transients: transients,
                                   threshold: thresholdValue)
    }

    /// - returns: the highest amplitude in the given array
    static func getPeakAmplitude(from buffer: [Float]) -> Transient.IndexedAmplitude {
        var peak: Float = Transient.min

        var index = 0
        for i in 0 ..< buffer.count {
            // store the absolute value of the sample
            let absSample = abs(buffer[i])
            if absSample > peak {
                peak = absSample
                index = i
            }
        }
        return Transient.IndexedAmplitude(amplitude: peak, index: index)
    }

    ///  - returns: the highest transient in the given array
    static func highestPeak(in peaks: [Transient]) -> Transient? {
        var max = Transient()

        for i in 0 ..< peaks.count {
            let item = peaks[i]
            if item > max {
                max = item
            }
        }
        return max
    }
}
