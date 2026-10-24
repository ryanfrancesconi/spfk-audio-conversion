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
        /// The buffer holds the trim's window, plus only the context frames either side of it.
        let isPreTrimmed: Bool
        /// Frames of `buffer` before and after the window, read as the stretcher's context and
        /// never rendered. Nonzero only when the buffer is pre-trimmed.
        var contextBefore = 0
        var contextAfter = 0
    }

    /// The edit pipeline every read route shares: trim, channels, the mono conform, time/pitch,
    /// normalize and fades, then the ceiling.
    func processEdit(_ window: RenderWindow, fileFormat: AVAudioFormat, writingTo url: URL) async throws -> AVAudioPCMBuffer {
        let edit = window.edit

        let stretchInput: AVAudioPCMBuffer
        if edit.timePitch.isEmpty {
            let source = try window.buffer.applyingSourceStages(edit, isPreTrimmed: window.isPreTrimmed)
            stretchInput = try Self.conforming(source, toMono: conformToMono)
        } else {
            stretchInput = try await stretched(window)
        }

        var buffer = try stretchInput.applyingOutputStages(edit, timeScale: edit.timePitch.rate)

        let needsCeiling = edit.needsCeiling || conformToMono != nil

        if needsCeiling, !Self.writesFloatPCM(fileFormat: fileFormat, buffer: buffer.format, outputURL: url) {
            buffer = try applyingCeiling(buffer)
        }

        return buffer
    }

    /// Folds a 2-channel buffer to `source`; any other buffer, or a nil `source`, passes through.
    static func conforming(_ buffer: AVAudioPCMBuffer, toMono source: MonoSource?) throws -> AVAudioPCMBuffer {
        guard let source, buffer.format.channelCount == 2 else { return buffer }
        return try buffer.applyingChannelOperation(.mono(source))
    }

    /// The channel operations the render applies, in order, for describing them in its TRACK_LIST.
    var renderedChannelOperations: [ChannelOperation] {
        var operations = [edit.channels]

        if let conformToMono, edit.channels.outputChannelCount(forInput: 2) == 2 {
            operations.append(.mono(conformToMono))
        }

        return operations
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
        let format = audioFile.processingFormat

        guard audioFile.length > 0 else {
            // A file read whole is trimmed in memory, so its context is cut from the same buffer.
            let whole = try read(audioFile, frames: frameCapacity)
            let window = Self.window(for: safeEdit.trim, totalFrames: whole.frameLength, sampleRate: sampleRate)
            return try withContext(of: window, in: whole, edit: safeEdit)
        }

        let window = Self.window(for: safeEdit.trim, totalFrames: frameCapacity, sampleRate: sampleRate)
        let context = try readContext(around: window, totalFrames: frameCapacity, format: format)

        if context.before > 0 {
            audioFile.framePosition = AVAudioFramePosition(window.offset - context.before)
        } else if window.offset > 0 {
            audioFile.framePosition = AVAudioFramePosition(window.offset)
        }

        let buffer = try read(audioFile, frames: context.before + window.frameCount + context.after)

        return RenderWindow(
            buffer: buffer,
            edit: safeEdit,
            isPreTrimmed: window.offset > 0 || window.frameCount < frameCapacity,
            contextBefore: Int(context.before),
            contextAfter: Int(min(context.after, buffer.frameLength - min(buffer.frameLength, context.before + window.frameCount)))
        )
    }

    /// Reads `frames` from the file's current position.
    ///
    /// A read can return fewer frames than asked with more still in the file: a mono float WAV
    /// stops 980 frames short of 210900. Each further read overwrites its buffer, so it goes
    /// through a chunk.
    private func read(_ audioFile: AVAudioFile, frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frames) else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        try audioFile.read(into: buffer, frameCount: frames)

        if buffer.frameLength < frames,
           let chunk = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: Self.decodeChunkFrames) {
            while buffer.frameLength < frames {
                try Task.checkCancellation()

                try audioFile.read(into: chunk, frameCount: min(Self.decodeChunkFrames, frames - buffer.frameLength))
                guard chunk.frameLength > 0 else { break }

                try buffer.copy(from: chunk, frames: chunk.frameLength)
            }
        }

        guard buffer.frameLength > 0 else {
            throw NSError(description: "Read 0 frames from \(sourceURL.lastPathComponent)")
        }

        return buffer
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
        let context = try readContext(around: window, totalFrames: totalFrames, format: format)
        let readStart = window.offset - context.before
        let readFrames = context.before + window.frameCount + context.after

        if readStart > 0 {
            try decoder.seek(toFrame: AVAudioFramePosition(readStart))
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: readFrames),
              let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.decodeChunkFrames)
        else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        while buffer.frameLength < readFrames {
            try Task.checkCancellation()

            let wanted = min(Self.decodeChunkFrames, readFrames - buffer.frameLength)
            let read = try decoder.readNextChunk(into: chunk, frameCount: wanted)

            guard read > 0 else { break }

            try buffer.copy(from: chunk, frames: read)
        }

        guard buffer.frameLength > 0 else {
            throw NSError(description: "Read 0 frames from \(sourceURL.lastPathComponent)")
        }

        // A declared length a lossless track undershoots leaves the read short at the end, which
        // costs the trailing context first.
        let kept = buffer.frameLength - min(buffer.frameLength, context.before + window.frameCount)

        return RenderWindow(
            buffer: buffer,
            edit: safeEdit,
            isPreTrimmed: window.offset > 0 || window.frameCount < totalFrames,
            contextBefore: Int(context.before),
            contextAfter: Int(min(context.after, kept))
        )
    }
}
