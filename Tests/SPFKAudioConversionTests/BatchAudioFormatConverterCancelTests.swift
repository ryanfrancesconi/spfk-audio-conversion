// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// A cancelled batch throws, rather than handing back what finished before the cancel.
@Suite(.tags(.file))
final class BatchAudioFormatConverterCancelTests: BinTestCase {
    @Test func cancellingTheBatchThrows() async throws {
        deleteBinOnExit = true
        let sources = [TestBundleResources.shared.tabla_wav, TestBundleResources.shared.tabla_mp3].map {
            AudioFormatConverterSource(
                input: $0,
                output: bin.appending(component: "\($0.deletingPathExtension().lastPathComponent)-\($0.pathExtension).m4a", directoryHint: .notDirectory),
                options: AudioFormatConverterOptions(format: .m4a)
            )
        }

        let converter = await BatchAudioFormatConverter(inputs: sources)
        let task = Task { try await converter.start() }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}
