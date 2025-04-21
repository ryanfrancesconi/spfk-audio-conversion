// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKAudioC
import SPFKMetadata
import SPFKUtils

public enum Loudness {
    public static func analyze(url: URL) async throws -> LoudnessDescription {
        var tmpfile: URL?

        defer {
            if let tmpfile, tmpfile.exists {
                Log.debug("Removing tmpfile at", tmpfile.path)
                try? tmpfile.delete()
            }
        }

        do {
            let tmpname = url.deletingPathExtension().lastPathComponent + "_\(Entropy.uniqueId)"
            let tmpfileOutput = url.deletingLastPathComponent().appendingPathComponent(tmpname)
            tmpfile = try await AudioTools.createLoopedAudio(input: url, output: tmpfileOutput, minimumDuration: 5)

        } catch {
            // Log.error(error)
        }

        let url = tmpfile ?? url

        guard let scanner = LoudnessScanner(path: url.path) else {
            throw NSError(description: "Failed to analyze '\(url.lastPathComponent)'")
        }

        return LoudnessDescription(
            lufs: scanner.lufs.isFinite ? scanner.lufs : nil,
            loudnessRange: scanner.loudnessRange.isFinite ? scanner.loudnessRange : nil,
            truePeak: scanner.truePeak.isFinite ? scanner.truePeak : nil
        )
    }
}
