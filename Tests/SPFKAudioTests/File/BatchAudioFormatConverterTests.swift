// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.file))
class BatchAudioFormatConverterTests: BinTestCase {
    @Test func convertAll() async throws {
        deleteBinOnExit = true

        let sources = BundleResources.shared.audioCases.map {
            let output = bin.appending(component: "\($0.deletingPathExtension().lastPathComponent).m4a", directoryHint: .notDirectory)

            return AudioFormatConverterSource(
                input: $0,
                output: output,
                options: AudioFormatConverterOptions(format: .m4a)
            )
        }

        let converter = BatchAudioFormatConverter(inputs: sources)
        let results = try await converter.start(progressHandler: self)

        #expect(sources.count == 7)
        #expect(sources.count == results.count)

        let errors = results.compactMap { $0.error }
        #expect(errors.count == 2) // two name collisions

        #expect(bin.directoryContents?.count == 5)

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

extension BatchAudioFormatConverterTests: AsyncProgress1Delegate {
    func asyncProgress(event: SPFKUtils.AsyncProgress1Event) async {
        Log.debug(event)
    }
}
