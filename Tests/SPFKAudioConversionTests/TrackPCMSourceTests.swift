// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct TrackPCMSourceTests {
    private let resources = TestBundleResources.shared

    @Test func theFirstTrackNeedsNoDecoder() async throws {
        let url = resources.dualaudio_m4a

        #expect(try await TrackPCMSource.source(for: url, audioTrack: nil) == nil)
        #expect(try await TrackPCMSource.source(for: url, audioTrack: .init(persistentTrackID: 1)) == nil)
    }

    @Test func aTrackTheFileDoesNotCarryNeedsNoDecoder() async throws {
        #expect(try await TrackPCMSource.source(for: resources.dualaudio_m4a, audioTrack: .init(persistentTrackID: 9)) == nil)
    }

    @Test func anotherTrackIsReadThroughTheAssetReader() async throws {
        let source = try await TrackPCMSource.source(for: resources.dualaudio_m4a, audioTrack: .init(persistentTrackID: 2))

        let reader = try #require(source as? AVAssetReaderPCMSource)
        #expect(reader.track.trackID == 2)
    }

    @Test func matroskaIsAlwaysDecoded() async throws {
        let source = try await TrackPCMSource.source(for: resources.dualaudio_mka, audioTrack: nil)

        #expect(source is MatroskaAudioDecoder)
    }
}
