// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase

/// Lets a waveform scan read Matroska audio, which is the whole reason ShadowTag wants the format:
/// an audio application showing no waveform for a file is not usable whatever else works.
///
/// ``SeekablePCMSource`` is the same samples with a movable playhead, which is what makes the file
/// playable rather than only drawable. Both are the adapter's whole job — the decoder emits
/// whatever a whole number of compressed packets produced, while a caller asks for an exact frame
/// count, and `consume` buffers the difference.
extension MatroskaAudioDecoder: SeekablePCMSource {
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

        let written = try consume(frameCount: frameCount, into: buffer)

        buffer.frameLength = written

        return written
    }
}
