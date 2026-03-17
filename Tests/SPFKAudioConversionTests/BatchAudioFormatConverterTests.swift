// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class BatchAudioFormatConverterTests: BinTestCase {
    @Test func convertAll() async throws {
        let sources = TestBundleResources.shared.audioCases.map {
            let output = bin.appending(
                component: "\($0.deletingPathExtension().lastPathComponent).m4a",
                directoryHint: .notDirectory,
            )

            return AudioFormatConverterSource(
                input: $0,
                output: output,
                options: AudioFormatConverterOptions(format: .m4a),
            )
        }

        let converter = await BatchAudioFormatConverter(inputs: sources)
        await converter.update(delegate: self)

        let results = try await converter.start()

        #expect(sources.count == results.count)

        let errors = results.compactMap(\.error)

        #expect(sources.count == 8) // could change when files are added to tests
        #expect(errors.count == 2) // could change

        #expect(bin.directoryContents?.count == 6)

        for result in results {
            switch result {
            case let .success(source: source):
                Log.debug("✅ \(source)")

            case let .failed(source: source, error: error):
                Log.debug("❌ \(source), \(error)")
            }
        }
    }

    // MARK: - Stress test: concurrent conversion to all output formats

    /// Converts every test audio case to each supported output format concurrently,
    /// exercising all converter backends (CoreAudio, LAME, libsndfile) in parallel.
    @Test func batchStressAllFormats() async throws {
        let inputs = TestBundleResources.shared.audioCases
        let outputFormats: [AudioFileType] = [.wav, .aiff, .caf, .m4a, .mp3, .flac, .ogg]

        var sources: [AudioFormatConverterSource] = []

        for input in inputs {
            let baseName = input.deletingPathExtension().lastPathComponent

            for format in outputFormats {
                let output = bin.appending(
                    component: "\(baseName)_to.\(format.pathExtension)",
                    directoryHint: .notDirectory,
                )

                sources.append(
                    AudioFormatConverterSource(
                        input: input,
                        output: output,
                        options: AudioFormatConverterOptions(format: format),
                    )
                )
            }
        }

        Log.debug("Batch stress: \(sources.count) conversions (\(inputs.count) inputs × \(outputFormats.count) formats)")

        let converter = await BatchAudioFormatConverter(inputs: sources)
        await converter.update(delegate: self)

        let results = try await converter.start()

        #expect(results.count == sources.count)

        var successCount = 0
        var failCount = 0

        for result in results {
            switch result {
            case let .success(source: source):
                successCount += 1

                // Verify the output file is valid audio
                let outputFile = try AVAudioFile(forReading: source.output)
                #expect(outputFile.duration > 0, "Zero duration: \(source.output.lastPathComponent)")

            case let .failed(source: source, error: error):
                failCount += 1
                Log.debug("❌ \(source.output.lastPathComponent): \(error)")
            }
        }

        Log.debug("Batch stress results: \(successCount) succeeded, \(failCount) failed out of \(results.count)")

        // Some inputs may not support all output paths (e.g., 6-channel → MP3).
        // At minimum the majority should succeed.
        #expect(successCount > sources.count / 2, "Too many failures: \(failCount) of \(sources.count)")
    }
}

extension BatchAudioFormatConverterTests: @unchecked Sendable, BatchAudioFormatConverterDelegate {
    func batchProgress(progressEvent: LoadStateEvent) async {
        Log.debug(progressEvent)
    }
}
