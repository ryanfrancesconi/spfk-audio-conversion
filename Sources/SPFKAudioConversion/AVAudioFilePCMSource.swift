// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKVideo

/// An `AVAudioFile` read front to back, for a file ``TrackPCMSource`` needs no decoder for.
public final class AVAudioFilePCMSource: SequentialPCMSource {
    private let file: AVAudioFile

    public var processingFormat: AVAudioFormat { file.processingFormat }
    public var totalFrameCount: AVAudioFramePosition { max(0, file.length) }

    public init(url: URL) throws {
        var file: AVAudioFile?
        try ExceptionTrap.withThrowing { file = try AVAudioFile(forReading: url) }

        guard let file else {
            throw NSError(description: "Unable to open \(url.lastPathComponent)")
        }

        self.file = file
    }

    public func readNextChunk(into buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount) throws -> AVAudioFrameCount {
        try ReversedAudioBuilder.readToEnd(file, into: buffer, frameCount: frameCount)
        return buffer.frameLength
    }
}

extension TrackPCMSource {
    /// A front-to-back reader for `audioTrack` of `url`: its decoder, or the ordinary file read
    /// when it needs none.
    public static func reader(
        for url: URL,
        audioTrack: AudioTrackDescription.ID?
    ) async throws -> any SequentialPCMSource {
        if let source = try await source(for: url, audioTrack: audioTrack) {
            return source
        }

        return try AVAudioFilePCMSource(url: url)
    }
}
