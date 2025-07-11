// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

public enum BatchAudioFormatConverterResult {
    case success(source: AudioFormatConverterSource)
    case failed(source: AudioFormatConverterSource, error: Error)

    public var source: AudioFormatConverterSource {
        switch self {
        case let .success(source: source):
            return source

        case let .failed(source: source, error: _):
            return source
        }
    }

    /// Non nil if the conversion failed for this source
    public var error: Error? {
        if case let .failed(_, error) = self {
            return error
        }

        return nil
    }
}
