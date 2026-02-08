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
        )

        let waveformData = try await parser.parse(url: url)

        // channel count for the file
        #expect(waveformData.channelCount == audioFile.fileFormat.channelCount)

        for channel in waveformData.floatChannelData {
            #expect(channel.count == audioFile.length)
        }
    }

    @Test func cancelTask() async throws {
        let input = TestBundleResources.shared.tabla_6_channel

        let task = Task<WaveformData, Error>(priority: .high) {
            let parser = WaveformDataParser(resolution: .veryHigh, eventHandler: { event in
                Log.debug(event.progress)
            })

            return try await parser.parse(url: input)
        }

        Task { @MainActor in
            try await Task.sleep(seconds: 0.009)
            task.cancel()
        }

        let result = await task.result
        Log.debug(result)
        #expect(!result.isSuccess)
        #expect(result.failureValue as? CancellationError != nil)
    }

    @Test func noDataChunk() async throws {
        let url = TestBundleResources.shared.no_data_chunk
        let request = WaveformDataParser(resolution: .low)

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
