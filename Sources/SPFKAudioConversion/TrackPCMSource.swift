// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKVideo

/// Chooses the decoder for one audio track of a file, when `ExtAudioFile` cannot reach it.
public enum TrackPCMSource {
    /// A decoder for `audioTrack` of `url`, or `nil` when the ordinary file read already gets it.
    ///
    /// `ExtAudioFile` reads only the first audio track, and opens neither Matroska nor MXF. A
    /// selection naming the first track, or one the file does not carry, is the ordinary read.
    public static func source(
        for url: URL,
        audioTrack: AudioTrackDescription.ID?
    ) async throws -> (any SeekablePCMSource)? {
        let fileType = AudioFileType(pathExtension: url.pathExtension)

        if fileType?.isMatroska == true {
            return try MatroskaAudioDecoder(url: url, audioTrack: audioTrack)
        }

        if fileType?.isAVAudioFileReadable == false {
            return try await AVAssetReaderPCMSource(url: url, audioTrack: audioTrack)
        }

        guard let audioTrack,
              await AVURLAsset(url: url).holdsAudioTrackOtherThanTheFirst(audioTrack)
        else { return nil }

        return try await AVAssetReaderPCMSource(url: url, audioTrack: audioTrack)
    }
}
