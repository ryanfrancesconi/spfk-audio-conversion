// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.tags(.file))
class WaveformDataParserTests: BinTestCase {
    @Test func parse() async throws {
        let url = TestBundleResources.shared.tabla_6_channel

        let parser = WaveformDataParser(
            resolution: .low,
            priority: .medium,
        )

        let waveformData = try await parser.parse(url: url)

        // channel count for the file
        #expect(waveformData.channelCount == 6)

        for channel in waveformData.floatChannelData {
            #expect(channel.count == 1315)
        }
    }

    // (25 iterations) took 0.09867474999919068 seconds.
    // (50 iterations) took 0.19027300000016112 seconds.
    // (1000 iterations) took 3.5749457916608662 seconds.
    @Test(arguments: [25, 50, 1000]) func parseWithBenchmark(loopCount: Int) async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function) (\(loopCount) iterations)"); defer { benchmark.stop() }

        for _ in 0 ..< loopCount {
            try await parse()
        }
    }

    @Test func parseLossless() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)")
        defer { benchmark.stop() }

        let url = TestBundleResources.shared.cowbell_wav

        let audioFile = try AVAudioFile(forReading: url)
        #expect(audioFile.length == 88201)
        #expect(audioFile.fileFormat.sampleRate == 44100)
        #expect(audioFile.duration == 2.0000226757369615)

        let parser = WaveformDataParser(
            resolution: .lossless,
            priority: .medium,
        )

        let waveformData = try await parser.parse(url: url)

        // channel count for the file
        #expect(waveformData.channelCount == audioFile.fileFormat.channelCount)

        for channel in waveformData.floatChannelData {
            #expect(channel.count == audioFile.length)
        }
    }

    @Test func cancel() async throws {
        let input = TestBundleResources.shared.tabla_6_channel

        let parser = WaveformDataParser(
            resolution: .lossless,
            priority: .low,
        )

        Task {
            try await Task.sleep(seconds: 0.005)
            await parser.cancel()
        }

        await #expect(throws: CancellationError.self) {
            _ = try await parser.parse(url: input)
        }
    }

    @Test func noDataChunk() async throws {
        let url = TestBundleResources.shared.no_data_chunk
        let request = WaveformDataParser(resolution: .low, priority: .low)

        await #expect(throws: (any Error).self) {
            do {
                _ = try await request.parse(url: url)
            } catch {
                Log.error(error)

                #expect(
                    error.localizedDescription.contains("No audio was found")
                )

                throw error
            }
        }
    }
}
