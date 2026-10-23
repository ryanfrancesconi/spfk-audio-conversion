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
}
