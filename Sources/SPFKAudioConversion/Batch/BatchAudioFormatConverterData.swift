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
    /// Because ``FileSystem/nextAvailableURL(_:delimiter:suffix:)`` only sees what is on disk,
    /// each resolved slot is immediately claimed with a zero-byte placeholder file. This ensures
    /// the next call in the loop skips that slot — both within this batch and for any other
    /// process looking at the same directory. The source's conflict scheme is then downgraded
    /// to `.overwrite` so the converter removes the placeholder and writes normally.
    public func resolveUniqueConflicts() {
        for i in sources.indices where sources[i].output.exists
            && sources[i].options.conflictScheme == .unique
        {
            let resolved = FileSystem.nextAvailableURL(sources[i].output)
            FileManager.default.createFile(atPath: resolved.path, contents: nil)
            sources[i].output = resolved
            sources[i].options.conflictScheme = .overwrite
        }
    }
}
