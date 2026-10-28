// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKVideo

/// Builds a reversed float32 CAF of one audio track, for playing a file backwards by playing the
/// result forwards.
///
/// Two passes, each reading forwards: the source is decoded into a temporary CAF, which is then
/// copied backwards in chunks. So no route needs a backward seek, and the frame count is what the
/// decode produced rather than what the container declares.
public enum ReversedAudioBuilder {
    public static let chunkFrames: AVAudioFrameCount = 1 << 18

    /// Writes the reversal of `audioTrack` of `source` to `destination`, a `.caf` path. Both
    /// temporary files are deleted on a throw or a cancel, and the forward one on success too.
    /// - Parameter progress: 0 ... 1 across both passes. The first pass reports only when the
    ///   source declares a length.
    public static func build(
        source: URL,
        audioTrack: AudioTrackDescription.ID?,
        into destination: URL,
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> (frameCount: Int, sampleRate: Double) {
        try await build(source: source, audioTrack: audioTrack, into: destination, chunkFrames: chunkFrames, progress: progress)
    }

    static func build(
        source: URL,
        audioTrack: AudioTrackDescription.ID?,
        into destination: URL,
        chunkFrames: AVAudioFrameCount,
        progress: @Sendable (Double) -> Void
    ) async throws -> (frameCount: Int, sampleRate: Double) {
        let forward = destination.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString)-forward.caf")

        defer { try? FileManager.default.removeItem(at: forward) }

        do {
            let decoded = try await decodeForward(source: source, audioTrack: audioTrack, into: forward, chunkFrames: chunkFrames) {
                progress($0 / 2)
            }

            guard decoded.frameCount > 0 else {
                throw NSError(description: "No audio could be decoded from \(source.lastPathComponent)")
            }

            let written = try copyBackwards(from: forward, frameCount: decoded.frameCount, into: destination, chunkFrames: chunkFrames) {
                progress(0.5 + $0 / 2)
            }

            guard written == decoded.frameCount else {
                throw NSError(description: "Reversing \(source.lastPathComponent) wrote \(written) frames, not \(decoded.frameCount)")
            }

            return decoded

        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: - Pass 1

    private static func decodeForward(
        source: URL,
        audioTrack: AudioTrackDescription.ID?,
        into forward: URL,
        chunkFrames: AVAudioFrameCount,
        progress: (Double) -> Void
    ) async throws -> (frameCount: Int, sampleRate: Double) {
        let reader = try await TrackPCMSource.reader(for: source, audioTrack: audioTrack)
        return try decode(format: reader.processingFormat, declaredFrames: reader.totalFrameCount, into: forward, chunkFrames: chunkFrames, progress: progress) { chunk, wanted in
            chunk.frameLength = try trapping { try reader.readNextChunk(into: chunk, frameCount: wanted) }
        }
    }

    /// `AVAudioFile` throws `eofErr` for a read at the end rather than returning nothing.
    static func readToEnd(_ file: AVAudioFile, into chunk: AVAudioPCMBuffer, frameCount: AVAudioFrameCount) throws {
        do {
            try ExceptionTrap.withThrowing { try file.read(into: chunk, frameCount: frameCount) }
        } catch let error as NSError where error.domain == NSOSStatusErrorDomain && error.code == eofErr {
            chunk.frameLength = 0
        }
    }

    /// Reads until a chunk comes back empty, never to a declared length.
    private static func decode(
        format: AVAudioFormat,
        declaredFrames: AVAudioFramePosition,
        into forward: URL,
        chunkFrames: AVAudioFrameCount,
        progress: (Double) -> Void,
        read: (AVAudioPCMBuffer, AVAudioFrameCount) throws -> Void
    ) throws -> (frameCount: Int, sampleRate: Double) {
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(description: "Failed to allocate a decode buffer")
        }

        let output = try makeWriter(at: forward, format: format)
        var frameCount = 0

        while true {
            try Task.checkCancellation()

            try read(chunk, chunkFrames)
            guard chunk.frameLength > 0 else { break }

            try ExceptionTrap.withThrowing { try output.write(from: chunk) }
            frameCount += Int(chunk.frameLength)

            if declaredFrames > 0 {
                progress(min(1, Double(frameCount) / Double(declaredFrames)))
            }
        }

        return (frameCount, format.sampleRate)
    }

    // MARK: - Pass 2

    private static func copyBackwards(
        from forward: URL,
        frameCount: Int,
        into destination: URL,
        chunkFrames: AVAudioFrameCount,
        progress: (Double) -> Void
    ) throws -> Int {
        let input = try trapping { try AVAudioFile(forReading: forward) }
        let format = input.processingFormat

        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(description: "Failed to allocate a reverse buffer")
        }

        let output = try makeWriter(at: destination, format: format)
        var position = frameCount
        var written = 0

        while position > 0 {
            try Task.checkCancellation()

            let frames = min(Int(chunkFrames), position)
            position -= frames

            try ExceptionTrap.withThrowing {
                input.framePosition = AVAudioFramePosition(position)
                try input.read(into: chunk, frameCount: AVAudioFrameCount(frames))
            }

            guard Int(chunk.frameLength) == frames else {
                throw NSError(description: "Read \(chunk.frameLength) frames at \(position), not \(frames)")
            }

            let reversed = try chunk.reverse()
            try ExceptionTrap.withThrowing { try output.write(from: reversed) }
            written += frames

            progress(Double(written) / Double(frameCount))
        }

        return written
    }

    /// An interleaved float32 CAF taking buffers in `format`.
    private static func makeWriter(at url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        var settings = format.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 32
        settings[AVLinearPCMIsFloatKey] = true
        settings[AVLinearPCMIsNonInterleaved] = false

        return try trapping {
            try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
    }

    /// AVFoundation raises Objective-C exceptions, which Swift cannot catch, on top of the errors it
    /// throws; this turns either into a thrown error.
    private static func trapping<T>(_ body: @escaping () throws -> T) throws -> T {
        var result: T?
        try ExceptionTrap.withThrowing { result = try body() }

        guard let result else {
            throw NSError(description: "The call returned no value")
        }

        return result
    }
}
