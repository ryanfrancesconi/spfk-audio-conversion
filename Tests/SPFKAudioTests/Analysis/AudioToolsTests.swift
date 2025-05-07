// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import Numerics
@testable import SPFKAudio
import SPFKMetadata
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
final class AudioToolsTests: BinTestCase {
    @Test func loopedAudio() async throws {
        let url = BundleResources.shared.cowbell_wav
        let initialDuration = try AVAudioFile(forReading: url).duration

        let output: URL = try await AudioTools.createLoopedAudio(input: url, minimumDuration: 10)
        let duration = try AVAudioFile(forReading: output).duration

        #expect(duration > initialDuration && duration <= 10)
    }
}
