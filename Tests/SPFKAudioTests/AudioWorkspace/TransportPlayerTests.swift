// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKBase
import Testing

@Suite(.serialized, .tags(.realtime))
final class TransportPlayerTests: TransportPlayerTestCase {
    @Test func formats() async throws {
        try await setup()
        let player = try #require(player)

        for url in TestBundleResources.shared.audioCases {
            try await player.load(url: url)
        }

        #expect(player.formats.count == 3) // dependence on the files in audioCases
    }

    @Test func play() async throws {
        try await setup()
        let player = try #require(player)
        player.mixer.volume = 0.5
        player.mixer.pan = -1

        try await player.load(url: TestBundleResources.shared.tabla_wav)
        try player.play(time: 0)

        try await wait(sec: 1)
        player.mixer.volume = 1
        player.mixer.pan = 1

        try await wait(sec: 1)
        try player.stop()
    }
}
