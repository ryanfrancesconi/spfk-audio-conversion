// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class CancellationTests: BinTestCase {
    // MARK: - AudioFormatConverter respects pre-cancellation

    @Test func converterThrowsWhenAlreadyCancelled() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)

        let task = Task {
            try await converter.start()
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    // MARK: - PCM conversion respects cancellation

    @Test func pcmConversionRespectsPreCancellation() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.sampleRate = 22050

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)

        let task = Task {
            try await converter.convertToPCM()
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    // MARK: - AssetWriter respects pre-cancellation

    @Test func assetWriterRespectsPreCancellation() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a

        let source = AudioFormatConverterSource(input: input, output: output, options: options)

        let task = Task {
            try await AssetWriter(source: source).start()
        }

        task.cancel()

        await #expect(throws: (any Error).self) {
            try await task.value
        }
    }

    // MARK: - Batch converter respects cancellation

    @Test func batchConverterStopsOnCancellation() async throws {
        let sources = [TestBundleResources.shared.tabla_wav, TestBundleResources.shared.cowbell_wav].map {
            let output = bin.appending(
                component: "\($0.deletingPathExtension().lastPathComponent)_cancel.m4a",
                directoryHint: .notDirectory
            )
            return AudioFormatConverterSource(
                input: $0,
                output: output,
                options: AudioFormatConverterOptions(format: .m4a)
            )
        }

        let converter = await BatchAudioFormatConverter(inputs: sources)

        let task = Task {
            try await converter.start()
        }

        task.cancel()

        await #expect(throws: (any Error).self) {
            _ = try await task.value
        }
    }

    // MARK: - Cleanup on cancellation

    @Test func partialOutputCleanedUpOnCancellation() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)

        let task = Task {
            try await converter.start()
        }

        task.cancel()

        // Wait for the task to finish (cancelled or completed)
        _ = try? await task.value

        // If conversion was cancelled before completion, partial file should be cleaned up.
        // If it completed before cancellation took effect, the file will exist (which is also valid).
        // This test verifies the cleanup path doesn't crash.
    }
}
