import AVFoundation
@testable import SPFKAudio
@testable import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.file))
class DynamicPCMBufferTests: BinTestCase {
    @Test func createElements() throws {
        let url = TestBundleResources.shared.tabla_wav
        let buffer = try DynamicPCMBuffer(url: url)

        #expect(buffer.channelCount == 2)
        #expect(buffer.frameLength == 210900)
        #expect(buffer.format == AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        #expect(buffer.rms == 0.05196464)

        let peak = try #require(buffer.peak())

        #expect(peak.amplitude == 0.98115706)
        #expect(peak.time == 2.1973333333333334)

        let elements = try #require(buffer.elements())

        #expect(elements.elements.count == 5)
    }

    @Test func loopBuffer() throws {
        let url = TestBundleResources.shared.tabla_wav

        guard let buffer = try AVAudioPCMBuffer(url: url) else {
            Issue.record("Failed to create buffer")
            return
        }

        let duplicatedBuffer = try buffer.loop(numberOfDuplicates: 4)

        #expect(duplicatedBuffer.frameLength == buffer.frameLength * 4)
    }
}
