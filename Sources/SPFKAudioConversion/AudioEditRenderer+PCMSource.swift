// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKVideo

extension AudioEditRenderer {
    /// A reader for ``audioTrack`` when it names a track other than the first of an
    /// AVFoundation-readable file, which `AVAudioFile` cannot reach. `nil` otherwise.
    func selectedTrackReader() async throws -> AVAssetReaderPCMSource? {
        guard let audioTrack,
              await AVURLAsset(url: sourceURL).holdsAudioTrackOtherThanTheFirst(audioTrack)
        else { return nil }

        return try await AVAssetReaderPCMSource(url: sourceURL, audioTrack: audioTrack)
    }

    /// The selected track's own encoding, which the render writes back in place of the first
    /// track's.
    func fileFormat(of reader: AVAssetReaderPCMSource) async throws -> AVAudioFormat {
        guard let description = try await reader.track.load(.formatDescriptions).first else {
            return reader.processingFormat
        }

        return AVAudioFormat(cmAudioFormatDescription: description)
    }

    /// Decodes the trim window of `decoder` and applies the edit to it.
    ///
    /// The decoder reports what the container declares, which a lossless track undershoots and a
    /// lossy one overshoots, so the read stops at the first empty chunk rather than at a count.
    func readAndApplyEdit(from decoder: some SeekablePCMSource) throws -> AVAudioPCMBuffer {
        let format = decoder.processingFormat
        let totalFrames = AVAudioFrameCount(max(0, decoder.totalFrameCount))

        guard totalFrames > 0 else {
            throw NSError(description: "No audio could be decoded from \(sourceURL.lastPathComponent)")
        }

        let safeEdit = edit.clampingFadesToTrim(fileDuration: Double(totalFrames) / format.sampleRate)
        let window = Self.window(for: safeEdit.trim, totalFrames: totalFrames, sampleRate: format.sampleRate)

        if window.offset > 0 {
            try decoder.seek(toFrame: AVAudioFramePosition(window.offset))
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window.frameCount),
              let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.decodeChunkFrames)
        else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        while buffer.frameLength < window.frameCount {
            try Task.checkCancellation()

            let wanted = min(Self.decodeChunkFrames, window.frameCount - buffer.frameLength)
            let read = try decoder.readNextChunk(into: chunk, frameCount: wanted)

            guard read > 0 else { break }

            try buffer.copy(from: chunk, frames: read)
        }

        guard buffer.frameLength > 0 else {
            throw NSError(description: "Read 0 frames from \(sourceURL.lastPathComponent)")
        }

        let isPreTrimmed = window.offset > 0 || window.frameCount < totalFrames

        return try buffer.applying(safeEdit, isPreTrimmed: isPreTrimmed)
    }
}
