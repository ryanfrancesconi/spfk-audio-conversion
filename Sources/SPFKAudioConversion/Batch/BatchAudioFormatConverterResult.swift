// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Foundation
import SPFKBase

public enum BatchAudioFormatConverterResult: Sendable {
    case success(source: AudioFormatConverterSource)
    case failed(source: AudioFormatConverterSource, error: Error)

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
