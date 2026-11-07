// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKBase

/// An `AVAudioFile` open or read that failed, with where in the file it failed. `AVAudioFile` can
/// fail without setting an error at all, which leaves nothing else to go on.
public enum AudioFileReadError: LocalizedError {
    case openFailed(URL, underlying: any Error)
    case readFailed(URL, framePosition: Int64, length: Int64, underlying: any Error)

    public var underlying: any Error {
        switch self {
        case let .openFailed(_, underlying), let .readFailed(_, _, _, underlying): underlying
        }
    }

    public var errorDescription: String? {
        let detail = underlying.messageDetail

        return switch self {
        case let .openFailed(url, _):
            "\(url.lastPathComponent) could not be opened (\(detail))"
        case let .readFailed(url, framePosition, length, _):
            "\(url.lastPathComponent) could not be read at frame \(framePosition) of \(length) (\(detail))"
        }
    }
}
