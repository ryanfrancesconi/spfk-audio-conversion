// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFoundation

extension AVAudioPCMBuffer {
    public var duration: TimeInterval {
        TimeInterval(frameLength) / format.sampleRate
    }

    public var rmsValue: Float {
        guard let data = floatChannelData else { return 0 }

        var rms: Float = 0.0
        for i in 0 ..< Int(format.channelCount) {
            var channelRms: Float = 0.0
            vDSP_rmsqv(data[i], 1, &channelRms, vDSP_Length(frameLength))
            rms += abs(channelRms)
        }
        let value = rms / Float(format.channelCount)
        return value
    }

    /// Returns internal buffer as an `Array` of `Float` Arrays.
    ///
    /// - `floatChannelData?[X]` will contain an Array of channel length samples as `Float`
    public var floatData: FloatChannelData? {
        // Do we have PCM channel data?
        guard let internalData = floatChannelData else { return nil }

        let channelCount = Int(format.channelCount)
        let size = Int(frameLength)
        let zeros = Array<Float>(repeating: 0, count: size)

        // Preallocate our Array so we're not constantly thrashing while resizing as we append.
        var result = Array(repeating: zeros, count: channelCount)

        // Loop across our channels...
        for channel in 0 ..< channelCount {
            // Make sure we go through all of the frames...
            for sampleIndex in 0 ..< size {
                result[channel][sampleIndex] = internalData[channel][sampleIndex * stride]
            }
        }
        return result
    }
}
