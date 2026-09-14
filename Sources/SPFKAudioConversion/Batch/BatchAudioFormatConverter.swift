// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKBase
import SPFKUtils

/// Converts multiple audio files concurrently using a sliding window of up to 8 tasks.
///
/// Create with an array of ``AudioFormatConverterSource`` values, optionally assign a
/// ``BatchAudioFormatConverterDelegate`` for progress, then call ``start()``. The batching itself is
/// `BatchFileConverter`'s.
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

    /// Converts all sources, returning a result for each (success or failure with error) **in the
    /// order the sources were given**, which is not the order they complete in.
    public func start() async throws -> [Result] {
        let sources = await data.sources
        let batchSize = await data.batchSize

        let results = try await BatchFileConverter(sources, batchSize: batchSize).start(
            progress: { [weak self] _, _, result in
                await self?.sendProgress(for: result.work)
            },
            convert: { source in
                let converter = AudioFormatConverter(source: source)
                try await converter.start()
                // The converter's source carries the options actually applied, and any
                // adjustments it had to make — the local copy predates both.
                return await converter.source
            }
        )

        return results.map { result in
            switch result {
            case let .success(source): .success(source: source)
            case let .failed(source, error): .failed(source: source, error: error)
            }
        }
    }

    private func sendProgress(for source: AudioFormatConverterSource) async {
        guard let delegate else { return }

        await data.increment()
        let progress: UnitInterval = await data.percent
        let string = "Converted \(source.output.lastPathComponent)"

        await delegate.batchProgress(progressEvent: .loading(string: string, progress: progress))
    }
}

/// Receives progress events from a ``BatchAudioFormatConverter``.
public protocol BatchAudioFormatConverterDelegate: AnyObject, Sendable {
    /// Called after each file completes (success or failure).
    func batchProgress(progressEvent: LoadStateEvent) async
}
