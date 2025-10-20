// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
class WaveformDataCacheTests: BinTestCase {
    lazy var cacheFile1 = bin.appending(component: "waveformDataCache.xml")
    lazy var cacheFile2 = bin.appending(component: "waveformDataCache.txt")

    @Test func serialize() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        deleteBinOnExit = false
        let cache = WaveformDataCache()

        for file in BundleResources.shared.audioCases {
            let waveformData = try await WaveformDataParser(resolution: .medium).parse(url: file)

            await cache.insert(
                value: waveformData,
                for: file
            )
        }

        let data = try await cache.encode()
        let strongData = try #require(data)
        let base64String = strongData.base64EncodedString()

        try strongData.write(to: cacheFile1)
        try base64String.write(to: cacheFile2, atomically: false, encoding: .utf8)

        let newCache = try WaveformDataCache(data: strongData)
        #expect(await cache.collection == newCache.collection)
        
        try await reparse()
    }
    
    private func reparse() async throws {
        // let data = try Data.
    }
}
