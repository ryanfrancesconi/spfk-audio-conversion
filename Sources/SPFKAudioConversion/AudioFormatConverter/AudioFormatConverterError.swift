// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation

/// A conversion ``AudioFormatConverter`` refuses before reading or writing anything.
public enum AudioFormatConverterError: LocalizedError, Equatable {
    /// The output is the file being converted, which writing it would destroy.
    case outputReplacesInput(URL)

    /// The file holds more frames than one buffer can, over six hours at 192 kHz.
    case tooLongToRender(URL)

    public var errorDescription: String? {
        switch self {
        case let .outputReplacesInput(url):
            "Converting \(url.lastPathComponent) would replace it. Choose a different folder or format."
        case let .tooLongToRender(url):
            "\(url.lastPathComponent) is too long to render in one piece."
        }
    }
}
