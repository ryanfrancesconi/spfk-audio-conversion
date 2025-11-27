// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKBase
import Testing

@Suite(.tags(.file))
class WaveformDataParserTests: BinTestCase {
    @Test func parse() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let url = TestBundleResources.shared.tabla_6_channel

        let parser = WaveformDataParser(
            resolution: .low,
            priority: .medium
        )

        let waveformData = try await parser.parse(url: url)

        // channel count for the file
        #expect(waveformData.channelCount == 6)

        for channel in waveformData.floatChannelData {
            #expect(channel.count == 1315)
        }
    }

    @Test func parseLossless() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let url = TestBundleResources.shared.cowbell_wav

        let audioFile = try AVAudioFile(forReading: url)
        #expect(audioFile.length == 88201)
        #expect(audioFile.fileFormat.sampleRate == 44100)
        #expect(audioFile.duration == 2.0000226757369615)

        let parser = WaveformDataParser(
            resolution: .lossless,
            priority: .medium
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
            resolution: .low,
            priority: .low
        )

        Task {
            try await Task.sleep(seconds: 0.11)
            await parser.cancel()
        }

        try await wait(sec: 0.1)

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

// MARK: - Experiments

extension WaveformDataParserTests {
    // The `getAudioSamples` function returns the naturtal time scale and
    // an array of single-precision values that represent an audio resource.
    static func getAssetSamples(url: URL) async throws -> [Float] {
        let asset = AVAsset(url: url)

        let reader = try AVAssetReader(asset: asset)

        guard let track = try await asset.load(.tracks).first else {
            throw NSError(description: "didn't find an asset track")
        }

        let outputSettings: [String: Int] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsBigEndianKey: 0,
            AVLinearPCMIsFloatKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: 1,
        ]

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )

        reader.add(output)
        reader.startReading()

        var samplesData = [Float]()

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                throw NSError(description: "failed to copyNextSampleBuffer")
            }

            let bufferLength = CMBlockBufferGetDataLength(dataBuffer)
            let count = bufferLength / 4

            let data = [Float](unsafeUninitializedCapacity: count) { buffer, initializedCount in

                CMBlockBufferCopyDataBytes(
                    dataBuffer,
                    atOffset: 0,
                    dataLength: bufferLength,
                    destination: buffer.baseAddress!
                )

                initializedCount = count
            }

            samplesData.append(contentsOf: data)
        }

        return samplesData
    }
}
