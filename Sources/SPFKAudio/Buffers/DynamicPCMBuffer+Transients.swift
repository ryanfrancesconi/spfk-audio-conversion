// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKUtils

// TODO: update to async

extension DynamicPCMBuffer {
    public func cancelProcessing() {
        _abortFlag = true
    }

    /// Find the single highest peak
    /// - Returns: A single `Transient`
    public func peak(bufferDuration: TimeInterval = 0.01,
                     startTime: TimeInterval? = nil,
                     endTime: TimeInterval? = nil) -> Transient? {
        defer {
            _abortFlag = false
        }

        guard internalBuffer.frameLength > 0 else { return nil }
        guard let floatData = internalBuffer.floatChannelData else { return nil }

        var value: Transient?

        var position: Int = 0
        var endFrame: AVAudioFrameCount = frameLength

        if let startTime = startTime {
            position = max(0, Int(format.sampleRate * startTime))
        }

        if let endTime = endTime {
            endFrame = min(frameLength, AVAudioFrameCount(format.sampleRate * endTime))
        }

        var peakValue: Float = Transient.min

        // the analysis buffer size
        let blockSize = Int(internalBuffer.format.sampleRate * bufferDuration)

        Log.debug("Total Frames", Int(endFrame) - position, "blockSize", blockSize)

        while true {
            if _abortFlag {
                Log.error("Aborted in peak()")
                return nil
            }

            if position + blockSize >= endFrame {
                // EOF
                break
            }
            for channel in 0 ..< channelCount {
                var block = Array(repeating: Float(0), count: blockSize)

                // fill the block with endFrame samples
                for i in 0 ..< block.count {
                    if i + position >= endFrame {
                        // EOF
                        break
                    }
                    block[i] = floatData[channel][i + position]
                }
                // scan the block
                let blockPeak = Self.getPeakAmplitude(from: block)

                if blockPeak.dBValue > peakValue {
                    // adjust to the middle of the block
                    let peakPosition = max(0, position - blockPeak.index)
                    let time = Double(peakPosition) / Double(format.sampleRate)

                    value = Transient(time: time,
                                      amplitude: blockPeak.amplitude,
                                      position: AVAudioFramePosition(peakPosition))
                    peakValue = blockPeak.dBValue
                }
                position += blockSize
            }
        }

        return value
    }

    public func elements(
        threshold: Float = -6,
        minimumTransientGapDuration: TimeInterval = 0.01,
        minimumElementDuration: TimeInterval = 0.2,
        bufferDuration: TimeInterval = 0.01,
        progressHandler: ((Double) -> Void)? = nil
    ) -> Transient.ElementData? {
        //
        defer {
            _isProcessing = false
            _abortFlag = false
        }
        //

        _isProcessing = true

        guard let transientCollection = Self.detectTransients(
            in: internalBuffer,
            threshold: threshold,
            bufferDuration: bufferDuration,
            progressHandler: { progress in
                progressHandler?(progress)
            }
        ) else {
            return nil
        }

        let transients = transientCollection.transients.sorted { lhs, rhs in
            lhs.time < rhs.time
        }
        Log.debug("scanning", transients.count, "transients with threshold", transientCollection.threshold)

        let minimumElementDuration = max(0.05, minimumElementDuration)

        var elementArray = [Transient.Element]()

        // the time measured between and endIndex and the time of the next startIndex
        var startTime: TimeInterval = -1

        for i in 0 ..< transients.count {
            if _abortFlag {
                Log.error("Aborted in elements()")
                _abortFlag = false
                return nil
            }
            let transient = transients[i]

            if startTime == -1 {
                if transient.passesThreshold {
                    startTime = transient.time
                }

            } else {
                if !transient.passesThreshold && transient.time - startTime >= minimumElementDuration {
                    let region = transients.filter {
                        $0.time >= startTime && $0.time <= transient.time
                    }
                    let syncPoint = Self.highestPeak(in: region)

                    let element = Transient.Element(inPoint: startTime,
                                                    outPoint: transient.time,
                                                    syncPoint: syncPoint?.time)

                    elementArray.append(element)
                    startTime = -1
                }
            }
        }

        Log.debug("Total transientCollection.transients", transientCollection.transients.count)

        progressHandler?(1)

        let data = Transient.ElementData(elements: elementArray,
                                         transientCollection: transientCollection)
        return data
    }
}
