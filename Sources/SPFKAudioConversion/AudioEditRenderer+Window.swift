// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase

extension AudioEditRenderer {
    /// The decoded trim window and the edit to apply to it.
    struct RenderWindow {
        let buffer: AVAudioPCMBuffer
        /// The edit with its fades clamped to the trim.
        let edit: AudioEditDescription
        /// The buffer already holds exactly the trim's window.
        let isPreTrimmed: Bool
    }

    /// The edit pipeline every read route shares: source stages, output stages, then the ceiling.
    func processEdit(_ window: RenderWindow, fileFormat: AVAudioFormat, writingTo url: URL) throws -> AVAudioPCMBuffer {
        let edit = window.edit

        var buffer = try window.buffer
            .applyingSourceStages(edit, isPreTrimmed: window.isPreTrimmed)
            .applyingOutputStages(edit)

        if edit.needsCeiling, !Self.writesFloatPCM(fileFormat: fileFormat, buffer: buffer.format, outputURL: url) {
            buffer = try applyingCeiling(buffer)
        }

        return buffer
    }

    /// Brings a buffer whose sample peak exceeds 0 dBFS under it, by ``renderSettings``' ceiling.
    func applyingCeiling(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let peak = try buffer.peak().amplitude
        guard peak > 1 else { return buffer }

        switch renderSettings.ceiling {
        case .scale: return try buffer.gain(1 / peak)
        case .limit: return try buffer.limited()
        }
    }

    /// Reads the trim window of `audioFile`.
    ///
    /// A file that cannot state its own length cannot be seeked by frame either, so it is read
    /// whole and trimmed in memory.
    func readWindow(from audioFile: AVAudioFile) async throws -> RenderWindow {
        // AVAudioFile.length returns 0 for some compressed formats (e.g. MP3) because
        // MPEG audio doesn't store a reliable frame count. Fall back to the asset duration.
        let frameCapacity: AVAudioFrameCount
        if audioFile.length > 0 {
            frameCapacity = try .checked(audioFile.length, for: sourceURL)
        } else {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            frameCapacity = try .checked(
                roundingUp: duration.seconds * audioFile.processingFormat.sampleRate,
                for: sourceURL
            )
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let safeEdit = edit.clampingFadesToTrim(fileDuration: Double(frameCapacity) / sampleRate)

        // Read only the trim window. A 2 second trim out of an hour otherwise allocates the hour:
        // measured 1325 MB for 1.9 MB of output, and `SegmentDivider` runs four of these at once.
        let window = audioFile.length > 0
            ? Self.window(for: safeEdit.trim, totalFrames: frameCapacity, sampleRate: sampleRate)
            : (offset: AVAudioFrameCount(0), frameCount: frameCapacity)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: window.frameCount
        ) else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        if window.offset > 0 {
            audioFile.framePosition = AVAudioFramePosition(window.offset)
        }

        try audioFile.read(into: buffer, frameCount: window.frameCount)

        // A read can return fewer frames than asked with more still in the file: a mono float WAV
        // stops 980 frames short of 210900. Each further read overwrites its buffer, so it goes
        // through a chunk.
        if buffer.frameLength < window.frameCount,
           let chunk = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: Self.decodeChunkFrames) {
            while buffer.frameLength < window.frameCount {
                try Task.checkCancellation()

                try audioFile.read(into: chunk, frameCount: min(Self.decodeChunkFrames, window.frameCount - buffer.frameLength))
                guard chunk.frameLength > 0 else { break }

                try buffer.copy(from: chunk, frames: chunk.frameLength)
            }
        }

        guard buffer.frameLength > 0 else {
            throw NSError(description: "Read 0 frames from \(sourceURL.lastPathComponent)")
        }

        return RenderWindow(
            buffer: buffer,
            edit: safeEdit,
            isPreTrimmed: window.offset > 0 || window.frameCount < frameCapacity
        )
    }

    /// Decodes the trim window of `decoder`.
    ///
    /// The decoder reports what the container declares, which a lossless track undershoots and a
    /// lossy one overshoots, so the read stops at the first empty chunk rather than at a count.
    func readWindow(from decoder: some SeekablePCMSource) throws -> RenderWindow {
        let format = decoder.processingFormat
        let totalFrames = try AVAudioFrameCount.checked(max(0, decoder.totalFrameCount), for: sourceURL)

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

        return RenderWindow(
            buffer: buffer,
            edit: safeEdit,
            isPreTrimmed: window.offset > 0 || window.frameCount < totalFrames
        )
    }
}
