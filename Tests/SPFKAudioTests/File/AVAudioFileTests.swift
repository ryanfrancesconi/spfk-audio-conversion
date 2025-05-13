

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.file))
class AVAudioFileTests: BinTestCase {
    @Test func peak() async throws {
        let input = BundleResources.shared.tabla_wav
        let avFile = try AVAudioFile(forReading: input)

        let peak = try #require(avFile.peak)

        let expected = Peak(sampleRate: 48000, framePosition: 105472, amplitude: 0.98115706)

        #expect(peak == expected)
    }

    @Test func extract() async throws {
        let input = BundleResources.shared.pink_noise
        let avFile = try AVAudioFile(forReading: input)

        let output = bin.appending(component: "extracted.wav", directoryHint: .notDirectory)

        try await avFile.extract(to: output, from: 1, to: 3, fadeInTime: 1, fadeOutTime: 1, options: nil)

        #expect(output.exists)

        let outputAVFile = try AVAudioFile(forReading: output)

        #expect(outputAVFile.duration == 2)
    }
}
