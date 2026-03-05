// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Foundation
import SPFKBase

/// The outcome of a single file in a batch conversion.
public enum BatchAudioFormatConverterResult: Sendable {
    /// The conversion completed successfully.
    case success(source: AudioFormatConverterSource)

    /// The conversion failed with the associated error.
    case failed(source: AudioFormatConverterSource, error: Error)

    /// The source that was converted (available for both success and failure).
    public var source: AudioFormatConverterSource {
        switch self {
        case .success(source: let source):
            return source

        case .failed(source: let source, error: _):
            return source
        }
    }

    /// Non nil if the conversion failed for this source
    public var error: Error? {
        if case .failed(_, let error) = self {
            return error
        }

        return nil
    }
}
