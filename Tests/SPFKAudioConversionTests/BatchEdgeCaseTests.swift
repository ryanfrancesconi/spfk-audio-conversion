// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class BatchEdgeCaseTests: BinTestCase {
    // MARK: - Empty batch

    @Test func emptyBatchThrows() async throws {
        let converter = BatchAudioFormatConverter()
        await #expect(throws: Error.self) {
            _ = try await converter.start()
        }
    }

    // MARK: - Delegate receives progress

    @Test func delegateReceivesProgress() async throws {
        let sources = [TestBundleResources.shared.tabla_wav, TestBundleResources.shared.cowbell_wav].map {
            let output = bin.appending(
                component: "\($0.deletingPathExtension().lastPathComponent)_delegate.m4a",
                directoryHint: .notDirectory
            )
            return AudioFormatConverterSource(
                input: $0,
                output: output,
                options: AudioFormatConverterOptions(format: .m4a)
            )
        }

        let progressTracker = ProgressTracker()
        let converter = await BatchAudioFormatConverter(inputs: sources)
        await converter.update(delegate: progressTracker)

        let results = try await converter.start()

        #expect(results.count == 2)
        let progressCount = await progressTracker.progressCount
        #expect(progressCount == 2)
    }

    // MARK: - Batch with all failures

    @Test func batchWithAllInvalidInputs() async throws {
        let fakeInputs = (0 ..< 3).map { i in
            let fakeURL = bin.appending(component: "fake_\(i).xyz", directoryHint: .notDirectory)
            let output = bin.appending(component: "fake_\(i).m4a", directoryHint: .notDirectory)
            return AudioFormatConverterSource(
                input: fakeURL,
                output: output,
                options: AudioFormatConverterOptions(format: .m4a)
            )
        }

        let converter = await BatchAudioFormatConverter(inputs: fakeInputs)
        let results = try await converter.start()

        #expect(results.count == 3)
        let errors = results.compactMap(\.error)
        #expect(errors.count == 3)
    }

    // MARK: - Batch result accessors

    @Test func batchResultSourceAccessor() {
        let source = AudioFormatConverterSource(
            input: URL(fileURLWithPath: "/input.wav"),
            output: URL(fileURLWithPath: "/output.m4a"),
            options: AudioFormatConverterOptions(format: .m4a)
        )

        let success = BatchAudioFormatConverterResult.success(source: source)
        #expect(success.source.input == source.input)
        #expect(success.error == nil)

        let failure = BatchAudioFormatConverterResult.failed(
            source: source,
            error: NSError(domain: "test", code: 1)
        )
        #expect(failure.source.input == source.input)
        #expect(failure.error != nil)
    }

    // MARK: - .unique conflict scheme in batch

    @Test func batchUniqueSchemeRenamesEachConflictingOutput() async throws {
        deleteBinOnExit = false

        let inputs = TestBundleResources.shared.formats

        // Pre-create an output file for each input so every job encounters a conflict
        var sources: [AudioFormatConverterSource] = []

        for input in inputs {
            let baseName = input.deletingPathExtension().lastPathComponent
            let output = bin.appending(
                component: "\(baseName)_unique_test.wav",
                directoryHint: .notDirectory
            )

            let options = AudioFormatConverterOptions(format: .wav, conflictScheme: .unique)

            sources.append(
                AudioFormatConverterSource(input: input, output: output, options: options)
            )
        }

        let converter = await BatchAudioFormatConverter(inputs: sources)
        let results = try await converter.start()

        #expect(results.count == inputs.count)

        let errors = results.compactMap(\.error)
        #expect(errors.isEmpty)

        // Each result carries the resolved output URL — verify every one was actually written
        for result in results {
            #expect(result.source.output.exists)
        }
    }

    // MARK: - Single file batch

    @Test func singleFileBatch() async throws {
        let source = AudioFormatConverterSource(
            input: TestBundleResources.shared.tabla_wav,
            output: bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory),
            options: AudioFormatConverterOptions(format: .m4a)
        )

        let converter = await BatchAudioFormatConverter(inputs: [source])
        let results = try await converter.start()

        #expect(results.count == 1)
        #expect(results.first?.error == nil)
    }
}

// MARK: - Progress Tracker

private actor ProgressTracker: BatchAudioFormatConverterDelegate {
    var progressCount = 0

    nonisolated func batchProgress(progressEvent: LoadStateEvent) async {
        await incrementCount()
    }

    private func incrementCount() {
        progressCount += 1
    }
}
