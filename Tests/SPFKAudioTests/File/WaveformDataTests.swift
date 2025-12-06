import AVFoundation
import OSLog
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.tags(.file))
class WaveformDataTests: TestCaseModel {
    let log = OSLog(subsystem: "com.spongefork.*", category: "PointsOfInterest")

    let waveformData: WaveformData = {
        let duration: TimeInterval = 60 * 2 // 2 minutes
        let sampleRate: Double = 44100
        let channelCount: Int = 2
        let frameCount: Int = Int(duration * sampleRate)

        var floatChannelData = Array(repeating: [Float](zeros: frameCount), count: channelCount)

        // fill data with dummy sequential numbers
        for n in 0 ..< channelCount {
            for i in 0 ..< frameCount {
                floatChannelData[n][i] = Float(i)
            }
        }

        return WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: WaveformDrawingResolution.lossless.samplesPerPoint,
            audioDuration: duration,
            sampleRate: sampleRate
        )
    }()

    @Test func data() throws {
        #expect(waveformData.floatChannelData.count == 2)
        #expect(waveformData.floatChannelData[0].count == 5_292_000)
        #expect(waveformData.floatChannelData[1].count == 5_292_000)
    }

    @Test func subdata_1() throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        let subdata = try waveformData.subdata(in: 0 ... 60) // 1 minute

        #expect(subdata.count == 2)

        for n in 0 ..< subdata.count {
            #expect(subdata[n].first == 0)
            #expect(subdata[n].last == 2_645_999.0)
        }
    }

    @Test func subdataClamped() throws {
        // range is out of bounds so will be clamped to 0 ... duration
        let subdata2 = try waveformData.subdata(in: -1 ... 121)
        #expect(subdata2[0].count == 44100 * 60 * 2)
    }
}

extension WaveformDataTests {
    // took 1.8553874999997788 seconds.
    @Test func subdata_real() async throws {
        // try await wait(sec: 5)

        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        //let url = TestBundleResources.shared.tabla_6_channel
        let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/Home Economics.wav")

        os_signpost(.begin, log: log, name: "parse")

        let parser = WaveformDataParser(
            resolution: .medium,
            priority: .medium,
            delegate: nil
        )

        let waveformData = try await parser.parse(url: url)
        os_signpost(.end, log: log, name: "parse")

        #expect(waveformData.channelCount == 2)

        os_signpost(.begin, log: log, name: "subdata")
        let subdata = try waveformData.subdata(in: 0 ... waveformData.audioDuration / 2)
        os_signpost(.end, log: log, name: "subdata")

        #expect(subdata.count == 2)
    }
}
