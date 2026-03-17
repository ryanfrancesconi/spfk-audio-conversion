// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKBase
import SPFKUtils

/// Converts multiple audio files concurrently using a sliding window of up to 8 tasks.
///
/// Create with an array of ``AudioFormatConverterSource`` values, optionally assign a
/// ``BatchAudioFormatConverterDelegate`` for progress, then call ``start()``.
public actor BatchAudioFormatConverter {
    /// Convenience alias for ``BatchAudioFormatConverterResult``.
    public typealias Result = BatchAudioFormatConverterResult

    /// Mutable state tracking sources, progress, and batch size.
    public var data = BatchAudioFormatConverterData()

    /// Optional delegate that receives progress events during conversion.
    public weak var delegate: BatchAudioFormatConverterDelegate?

    /// Sets or clears the progress delegate.
    public func update(delegate: BatchAudioFormatConverterDelegate?) async {
        self.delegate = delegate
    }

    /// Creates an empty batch converter.
    public init() {}

    /// Creates a batch converter pre-loaded with the given sources.
    public init(inputs sources: [AudioFormatConverterSource]) async {
        await data.update(sources: sources)
    }

    /// Converts all sources, returning a result for each (success or failure with error).
    public func start() async throws -> [Result] {
        let collection: [AudioFormatConverterSource] = await data.sources
        let count = await data.count
        let batchSize: Int = await data.batchSize

        guard collection.isNotEmpty else {
            throw NSError(description: "No files to process")
        }

        return try await batchMap(count: count, batchSize: batchSize) { [weak self] i -> Result? in
            guard collection.indices.contains(i) else { return nil }

            let source = collection[i]

            var result: Result

            do {
                let converter = AudioFormatConverter(source: source)
                try await converter.start()
                result = .success(source: source)
            } catch {
                result = .failed(source: source, error: error)
            }

            await self?.sendProgress(for: result)

            return result
        }
    }

    private func sendProgress(for result: Result) async {
        guard let delegate else { return }

        await data.increment()
        let progress: UnitInterval = await data.percent
        let string = "Converted \(result.source.output.lastPathComponent)"

        await delegate.batchProgress(progressEvent: .loading(string: string, progress: progress))
    }
}

/// Receives progress events from a ``BatchAudioFormatConverter``.
public protocol BatchAudioFormatConverterDelegate: AnyObject, Sendable {
    /// Called after each file completes (success or failure).
    func batchProgress(progressEvent: LoadStateEvent) async
}
