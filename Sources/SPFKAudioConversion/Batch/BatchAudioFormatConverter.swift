// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Foundation
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

        return try await withThrowingTaskGroup(
            of: Result?.self,
            returning: [Result].self
        ) { taskGroup in
            try Task.checkCancellation()

            @Sendable func worker(i: Int) async -> Result? {
                guard collection.indices.contains(i) else {
                    return nil
                }

                let source = collection[i]

                do {
                    let converter = AudioFormatConverter(source: source)
                    try await converter.start()
                    return .success(source: source)

                } catch {
                    return .failed(source: source, error: error)
                }
            }

            for i in 0 ..< batchSize {
                taskGroup.addTask {
                    await worker(i: i)
                }
            }

            var index: Int = batchSize
            var mutableResults = [Result]()

            func sendProgress(for result: Result) async {
                guard let delegate, count > 0 else { return }

                await data.increment()
                let progress: UnitInterval = await data.percent

                let prefix = result.error != nil ? "Error" : "Converted"

                await delegate.batchProgress(progressEvent: .loading(string: prefix, progress: progress))
            }

            for try await result in taskGroup {
                try Task.checkCancellation()

                if let result {
                    mutableResults.append(result)
                    await sendProgress(for: result)
                }

                if index < count {
                    // as a task finishes add another one to keep the batch size intact
                    taskGroup.addTask { [index] in
                        await worker(i: index)
                    }

                    index += 1
                }
            }

            return mutableResults
        }
    }
}

/// Receives progress events from a ``BatchAudioFormatConverter``.
public protocol BatchAudioFormatConverterDelegate: AnyObject {
    /// Called after each file completes (success or failure).
    func batchProgress(progressEvent: LoadStateEvent) async
}
