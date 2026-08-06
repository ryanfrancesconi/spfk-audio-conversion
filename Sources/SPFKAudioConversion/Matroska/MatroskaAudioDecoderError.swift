// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation

/// Errors thrown while decoding a Matroska or WebM file's audio.
public enum MatroskaAudioDecoderError: Error, Equatable, Sendable {
    /// The file parsed, but declares no audio track.
    case noAudioTrack(URL)

    /// A codec Matroska allows but this decoder does not describe to Core Audio. DTS and TrueHD are
    /// the ones a film is likely to carry.
    case unsupportedCodec(String)

    /// The codec is described, but the system has no decoder for it in this configuration.
    case decoderUnavailable(String)

    case bufferAllocationFailed

    /// The decoder was fed valid packets and failed anyway, which usually means a corrupt stream.
    case decodeFailed(URL)
}

// MARK: - LocalizedError

extension MatroskaAudioDecoderError: LocalizedError {
    /// Plain English rather than a localized string, matching the other error types in the audio
    /// packages — user-facing wording lives in the UI layer, where the catalogs are.
    public var errorDescription: String? {
        switch self {
        case let .noAudioTrack(url):
            "\(url.lastPathComponent) has no audio track"

        case let .unsupportedCodec(codecID):
            "\(codecID) is not an audio codec this app can decode"

        case let .decoderUnavailable(codecID):
            "No system decoder is available for \(codecID)"

        case .bufferAllocationFailed:
            "Could not allocate an audio buffer"

        case let .decodeFailed(url):
            "Failed to decode the audio in \(url.lastPathComponent)"
        }
    }
}
