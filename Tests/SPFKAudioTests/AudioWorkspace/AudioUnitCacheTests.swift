// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AEXML
import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.realtime))
final class AudioUnitCacheTests: BinTestCase, @unchecked Sendable {
    lazy var manager = AudioUnitCacheManager(cachesDirectory: bin)

    override init() async {
        await super.init()
    }

    func tearDown() async throws {
        await manager.dispose()
    }

    @Test(.disabled("this takes some time so best not to include in general runs"))
    func createCache() async throws {
        deleteBinOnExit = false
        try await manager.createCache()
    }

    let cacheDocument: AEXMLDocument? = {
        let string = """
        <effects cachedComponentCount="339">
            <au componentFlags="2" componentFlagsMask="0" componentManufacturer="1634758764" componentSubType="1752393830" componentType="1635083896" isEnabled="true" manufacturerName="Apple" name="AUHighShelfFilter" typeName="Effect" validation="Passed" version="1.6.0" />
            <au componentFlags="2" componentFlagsMask="0" componentManufacturer="1634758764" componentSubType="1684368505" componentType="1635083896" isEnabled="true" manufacturerName="Apple" name="AUDelay" typeName="Effect" validation="Passed" version="1.6.0" />
        </effects>
        """

        return try? AEXMLDocument(fromString: string)
    }()

    @Test func parseCache() async throws {
        guard let cacheDocument else {
            Issue.record("failed to load cache")
            return
        }

        // after the load is complete - these components are ready to use
        let response = try await manager.parse(cache: cacheDocument)

        // can test realtime adding and removing from the finder folder while waiting
        // try await wait(sec: 20)

        Log.debug(response.results.map(\.description))

        #expect(response.results.map(\.name) == ["AUHighShelfFilter", "AUDelay"])

        try await tearDown()
    }
}

extension AudioUnitCacheTests: AudioUnitCacheManagerDelegate {
    func handleAudioUnitCacheManager(event: AudioUnitCacheEvent) async {
        Log.debug(event)
    }
}
