// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKAudioC
import SPFKMetadata
import SPFKUtils

extension LoudnessDescription {
    public init(url: URL) throws {
        guard let scanner = LoudnessScanner(path: url.path) else {
            throw NSError(description: "Failed to analyze '\(url.lastPathComponent)'")
        }

        self = LoudnessDescription(
            lufs: scanner.lufs.isFinite ? scanner.lufs : nil,
            loudnessRange: scanner.loudnessRange.isFinite ? scanner.loudnessRange : nil,
            truePeak: scanner.truePeak.isFinite ? scanner.truePeak : nil
        )
    }
}
