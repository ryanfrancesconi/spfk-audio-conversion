// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// A source with no audio in it fails the PCM conversion rather than writing an empty file.
@Suite(.tags(.file))
final class EmptySourcePCMTests: BinTestCase {
    @Test func aSourceWithNoAudioThrows() async throws {
        deleteBinOnExit = true
        let output = bin.appending(component: "no_data_chunk.aif", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(source: AudioFormatConverterSource(
            input: TestBundleResources.shared.no_data_chunk,
            output: output,
            options: AudioFormatConverterOptions(format: .aiff)
        ))

        await #expect(throws: (any Error).self) {
            try await converter.start()
        }
        #expect(!output.exists)
    }
}
