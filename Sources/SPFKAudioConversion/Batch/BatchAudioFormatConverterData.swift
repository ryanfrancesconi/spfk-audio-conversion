// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKBase
import SPFKFileSystem

/// Mutable state for a ``BatchAudioFormatConverter``, tracking sources and progress.
public actor BatchAudioFormatConverterData {
    /// The conversion sources queued for processing.
    public private(set) var sources: [AudioFormatConverterSource] = []

    /// Total number of sources in this batch.
    public private(set) var count: Int = 0

    /// Maximum number of concurrent conversions (capped at `count`, default 8).
    public private(set) var batchSize: Int = 0

    /// Number of conversions completed so far.
    public private(set) var completed: Int = 0

    /// Fraction of conversions completed (0.0–1.0).
    public var percent: UnitInterval {
        guard count > 0 else { return 0 }

        return completed.double / count.double
    }

    /// Creates empty batch data.
    public init() {}

    /// Creates batch data pre-loaded with sources.
    public init(sources: [AudioFormatConverterSource]) async {
        update(sources: sources)
    }

    /// Replaces the source list and resets progress.
    public func update(sources: [AudioFormatConverterSource]) {
        self.sources = sources
        count = sources.count
        completed = 0
        batchSize = 8.clamped(to: 0 ... count)
    }

    /// Advances the completed count by one.
    public func increment() {
        completed += 1
    }

    /// Pre-resolves all `.unique` conflict scheme outputs before concurrent conversion begins.
    ///
    /// Iterates sources serially. For each `.unique` source whose output URL is already taken
    /// (on disk or claimed by an earlier source in this batch), the slot is advanced via
    /// ``FileSystem/nextAvailableURL(_:delimiter:suffix:)``. Every resolved URL — including
    /// ones that were not already taken — is immediately claimed with a zero-byte placeholder,
    /// so the next iteration sees it as occupied. The conflict scheme is then downgraded to
    /// `.overwrite` so the converter removes the placeholder and writes normally.
    public func resolveUniqueConflicts() {
        for i in sources.indices where sources[i].options.conflictScheme == .unique {
            let url = sources[i].output
            let resolved = url.exists ? FileSystem.nextAvailableURL(url) : url

            // Ensure the output directory exists before attempting to claim the slot.
            let directory = resolved.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let claimed = FileManager.default.createFile(atPath: resolved.path, contents: nil)
            if !claimed {
                Log.error("resolveUniqueConflicts: failed to claim placeholder at", resolved.path)
            }

            sources[i].output = resolved
            sources[i].options.conflictScheme = .overwrite
        }
    }
}
