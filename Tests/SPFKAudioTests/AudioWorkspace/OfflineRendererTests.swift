// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.engine))
final class OfflineRendererTests: AudioPlayerTestCase {
    let renderer = OfflineRenderer()

    @Test func render() async throws {
        deleteBinOnExit = false
        try await setup()
        guard let player else { return }
        try player.load(url: TestBundleResources.shared.counting_123456789_60BPM_48k)

        let url = bin.appendingPathComponent("render.wav", conformingTo: .wav)

        let prerender = {
            try player.schedule(from: 2, to: 4, when: 0)
            try player.play()
        }

        let postrender = {
            player.stop()
        }

        renderer.eventHandler = { Log.debug($0) }

        await renderer.render(
            engineManager: audioWorkspace.engineManager,
            to: url,
            duration: 2,
            renderUntilSilent: false,
            audioSettings: .waveStereo48k16bit,
            prerender: prerender,
            postrender: postrender
        )

        await renderer.convertAudio()
        renderer.cleanup()

        let output = try #require(renderer.convertedMixURL)

        let audioFile = try AVAudioFile(forReading: output)

        #expect(audioFile.duration == 2)
    }
}
