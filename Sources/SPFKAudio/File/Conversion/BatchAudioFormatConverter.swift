// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

public struct BatchAudioFormatConverter {
    public enum Result {
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

    var sources: [AudioFormatConverterSource]

    public init(inputs sources: [AudioFormatConverterSource]) {
        self.sources = sources
    }

    public func start(progressHandler: ((AsyncProgress1Event) -> Void)? = nil) async throws -> [Result] {
        try await withThrowingTaskGroup(
            of: Result?.self,
            returning: [Result].self
        ) { taskGroup in

            let collection: [AudioFormatConverterSource] = sources
            let count = collection.count
            let batchSize: Int = 8.clamped(to: 0 ... count)

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

            func sendProgress(for result: Result) {
                guard let progressHandler else { return }

                let progress: ProgressValue1 = (mutableResults.count.double / count.double)

                let prefix = result.error != nil ? "Error for " : "Converted "
                let string = prefix + result.source.input.lastPathComponent

                progressHandler(
                    (string: string, progress: progress)
                )
            }

            for try await result in taskGroup {
                try Task.checkCancellation()

                if let result {
                    mutableResults.append(result)
                    sendProgress(for: result)
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
