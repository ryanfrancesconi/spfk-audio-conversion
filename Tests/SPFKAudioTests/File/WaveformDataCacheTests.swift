// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
class WaveformDataCacheTests: BinTestCase {
    static func createCache() async throws -> WaveformDataCache {
        let cache = WaveformDataCache()

        for file in BundleResources.shared.audioCases {
            let waveformData = try await WaveformDataParser(resolution: .medium).parse(url: file)

            await cache.insert(
                value: waveformData,
                for: file
            )
        }

        return cache
    }

    @Test func serialize() async throws {
        let cache = try await Self.createCache()
        let data = try #require(await cache.data.dataRepresentation)
        let newCache = try WaveformDataCollection(data: data)

        #expect(await cache.data.collection == newCache.collection)
    }

    @Test func parse1() async throws {
        deleteBinOnExit = false
        
        let cache = try await Self.createCache()
        let data = try #require(await cache.data.dataRepresentation)

        let file = bin.appending(component: "waveformDataCache.xml")
        try data.write(to: file)

        let newCache = try parse(data: file)

        #expect(newCache.collection.count == 7)
    }

    @Test func parse2() async throws {
        let cache = try await Self.createCache()
        let base64String = try #require(await cache.data.base64EncodedString)

        let file = bin.appending(component: "waveformDataCache.txt")
        try base64String.write(to: file, atomically: false, encoding: .utf8)

        let newCache = try parse(base64Encoded: file)

        #expect(newCache.collection.count == 7)
    }

    private func parse(data file: URL) throws -> WaveformDataCollection {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let newData = try Data(contentsOf: file)
        return try WaveformDataCollection(data: newData)
    }

    private func parse(base64Encoded file: URL) throws -> WaveformDataCollection {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let newData = try String(contentsOf: file, encoding: .utf8)
        return try WaveformDataCollection(base64EncodedString: newData)
    }
}
