// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

public class BatchAudioFormatConverter {
    public typealias Result = BatchAudioFormatConverterResult

    public var data = BatchAudioFormatConverterData()

    public weak var delegate: BatchAudioFormatConverterDelegate?

    public init() {}

    public init(inputs sources: [AudioFormatConverterSource]) async {
        await self.data.update(sources: sources)
    }

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
                let progress: ProgressValue1 = await data.percent

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

public protocol BatchAudioFormatConverterDelegate: AnyObject {
    func batchProgress(progressEvent: LoadStateEvent) async
}
