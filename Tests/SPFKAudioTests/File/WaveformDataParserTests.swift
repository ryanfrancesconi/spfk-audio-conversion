// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
class WaveformDataParserTests: BinTestCase {
    @Test func parse() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let input = BundleResources.shared.tabla_6_channel

        let parser = WaveformDataParser(
            resolution: .low,
            priority: .low
        )

        let data = try await parser.parse(url: input)

        // channel count for the file
        #expect(data.count == 6)

        for channel in data {
            #expect(channel.count == 1315)
        }
    }

    @Test func cancel() async throws {
        let input = BundleResources.shared.tabla_6_channel

        let parser = WaveformDataParser(
            resolution: .low,
            priority: .low
        )

        Task {
            try await Task.sleep(seconds: 0.15)
            parser.cancel()
        }

        try await wait(sec: 0.1)

        await #expect(throws: CancellationError.self) {
            _ = try await parser.parse(url: input)
        }
    }

    @Test func noDataChunk() async throws {
        let input = BundleResources.shared.no_data_chunk
        let request = WaveformDataParser(resolution: .low, priority: .low)

        await #expect(throws: (any Error).self) {
            do {
                _ = try await request.parse(url: input)
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
