// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.realtime))
final class AudioUnitCacheTests: BinTestCase {
    lazy var manager = AudioUnitCacheManager(cachesDirectory: bin) { event in
        Log.debug(event)
    }

    override init() async {
        await super.init()
    }

    func tearDown() async throws {
        await manager.dispose()
    }

    @Test func createCache() async throws {
        deleteBinOnExit = false

        try await manager.createCache()
    }

    @Test func parseCache() async throws {
        deleteBinOnExit = false

        guard await manager.cacheExists else {
            Issue.record("run createCache() first")
            return
        }

        // after the load is complete - these components are ready to use
        let components = try await manager.load()

        // can test realtime adding and removing from the finder folder while waiting
        // try await wait(sec: 20)

        Log.debug(components.validationDescription)

        try await tearDown()
    }
}
