// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
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

    @Test func theReaderFallsBackToTheFileReadAndReadsItAll() async throws {
        let url = resources.tabla_wav
        let reader = try await TrackPCMSource.reader(for: url, audioTrack: nil)
        #expect(reader is AVAudioFilePCMSource)

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 4096))
        var total: AVAudioFramePosition = 0
        while case let read = try reader.readNextChunk(into: buffer, frameCount: 4096), read > 0 {
            total += AVAudioFramePosition(read)
        }

        #expect(try total == AVAudioFile(forReading: url).length)
    }

    @Test func theReaderUsesTheDecoderForAnotherTrack() async throws {
        let reader = try await TrackPCMSource.reader(for: resources.dualaudio_m4a, audioTrack: .init(persistentTrackID: 2))
        #expect(reader is AVAssetReaderPCMSource)
    }

    @Test func oggIsDecodedThroughLibsndfile() async throws {
        #expect(try await TrackPCMSource.source(for: resources.tabla_ogg, audioTrack: nil) is SndFilePCMSource)
        #expect(try await TrackPCMSource.source(for: resources.sine_opus, audioTrack: nil) is SndFilePCMSource)
    }
}
