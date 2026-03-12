// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

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
}

extension BatchAudioFormatConverterTests: @unchecked Sendable, BatchAudioFormatConverterDelegate {
    func batchProgress(progressEvent: LoadStateEvent) async {
        Log.debug(progressEvent)
    }
}
