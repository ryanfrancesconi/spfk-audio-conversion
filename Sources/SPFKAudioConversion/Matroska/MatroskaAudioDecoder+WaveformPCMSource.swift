// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase

/// Lets a waveform scan read Matroska audio, which is the whole reason ShadowTag wants the format:
/// an audio application showing no waveform for a file is not usable whatever else works.
///
/// The decoder emits whatever a whole number of compressed packets produced, while the scan asks
/// for an exact chunk. This buffers the difference — the only work the adapter does.
extension MatroskaAudioDecoder: WaveformPCMSource {
    public var totalFrameCount: AVAudioFramePosition {
        // The segment duration, which is what the container states. An upper bound on the audio
        // track when a sibling video track runs longer; the scan tolerates a short read.
        guard let duration = file.duration else { return 0 }

        return AVAudioFramePosition(duration * processingFormat.sampleRate)
    }

    public func readNextChunk(
        into buffer: AVAudioPCMBuffer,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioFrameCount {
        buffer.frameLength = 0

        var written: AVAudioFrameCount = 0

        while written < frameCount {
            guard let pending = try pendingBuffer() else {
                break
            }

            let taken = min(frameCount - written, pending.frameLength - pendingOffset)

            copy(from: pending, sourceOffset: pendingOffset, to: buffer, destinationOffset: written, frameCount: taken)

            written += taken
            pendingOffset += taken

            if pendingOffset >= pending.frameLength {
                clearPending()
            }
        }

        buffer.frameLength = written

        return written
    }

    /// Copies interleaved-by-channel float samples between two buffers of the same format.
    private func copy(
        from source: AVAudioPCMBuffer,
        sourceOffset: AVAudioFrameCount,
        to destination: AVAudioPCMBuffer,
        destinationOffset: AVAudioFrameCount,
        frameCount: AVAudioFrameCount
    ) {
        guard frameCount > 0,
              let sourceData = source.floatChannelData,
              let destinationData = destination.floatChannelData
        else {
            return
        }

        let channelCount = Int(min(source.format.channelCount, destination.format.channelCount))

        for channel in 0 ..< channelCount {
            let from = sourceData[channel].advanced(by: Int(sourceOffset))
            let to = destinationData[channel].advanced(by: Int(destinationOffset))
            to.update(from: from, count: Int(frameCount))
        }
    }
}
