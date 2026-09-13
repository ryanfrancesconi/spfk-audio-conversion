// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation

/// A conversion ``AudioFormatConverter`` refuses before reading or writing anything.
public enum AudioFormatConverterError: LocalizedError, Equatable {
    /// The output is the file being converted, which writing it would destroy.
    case outputReplacesInput(URL)

    public var errorDescription: String? {
        switch self {
        case let .outputReplacesInput(url):
            "Converting \(url.lastPathComponent) would replace it. Choose a different folder or format."
        }
    }
}
