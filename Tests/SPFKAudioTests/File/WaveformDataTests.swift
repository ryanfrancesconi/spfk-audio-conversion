import AVFoundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.tags(.file))
class WaveformDataTests {
    let waveformData: WaveformData = {
        let sampleRate: Double = 44100
        let channelCount: Int = 2

        var floatChannelData = Array(repeating: [Float](zeros: sampleRate.int), count: channelCount)

        // fill data with dummy sequential numbers
        for n in 0 ..< channelCount {
            for i in 0 ..< sampleRate.int {
                floatChannelData[n][i] = i.float
            }
        }

        return WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: WaveformDrawingResolution.lossless.samplesPerPoint,
            audioDuration: 1,
            sampleRate: sampleRate
        )
    }()

    @Test func data() throws {
        #expect(waveformData.floatChannelData.count == 2)
        #expect(waveformData.floatChannelData[0].count == 44100)
        #expect(waveformData.floatChannelData[1].count == 44100)
    }

    @Test func subdata() throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        let subdata = try waveformData.subdata(in: 0.1 ... 0.2)

        #expect(subdata.count == 2)

        for n in 0 ..< subdata.count {
            #expect(subdata[n].count == 4410)
            #expect(subdata[n][0] == 4410)
            #expect(subdata[n][4409] == 8819)
        }
    }

    @Test func subdataClamped() throws {
        // range is out of bounds so will be clamped to 0 ... duration
        let subdata2 = try waveformData.subdata(in: -1 ... 1)
        #expect(subdata2 == waveformData.floatChannelData)
    }
}

extension WaveformDataTests {
    // took 1.8553874999997788 seconds.
    @Test func subdata2() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        // let url = TestBundleResources.shared.tabla_6_channel
        let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/Home Economics.wav")

        let parser = WaveformDataParser(
            resolution: .veryHigh,
            priority: .medium,
            delegate: nil
        )

        let waveformData = try await parser.parse(url: url)
        #expect(waveformData.channelCount == 2)
        #expect(waveformData.floatChannelData[0].count == 1_040_166)

        let subdata = try waveformData.subdata(in: 0 ... waveformData.audioDuration / 2)

        #expect(subdata.count == 2)
        #expect(subdata[0].count == 520_083)
    }
}
