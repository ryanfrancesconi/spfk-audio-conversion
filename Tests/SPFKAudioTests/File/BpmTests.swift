import AVFoundation
import SPFKAudioC
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.tags(.file))
class BpmTests: TestCaseModel {
    @Test func drumloop_60() async throws {
        let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/60_drumloop.wav")
        let bpm = try await BpmAnalysis().process(url: url)
        #expect(bpm.isMultiple(of: 60))
    }

    @Test func drumloop_110() async throws {
        let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/110_drumloop.wav")
        let bpm = try await BpmAnalysis().process(url: url)
        #expect(bpm.isMultiple(of: 110))
    }

    @Test func drumloop_200() async throws {
        let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/200_drumloop.wav")
        let bpm = try await BpmAnalysis().process(url: url)
        #expect(bpm.isMultiple(of: 200))
    }

    @Test func drumloop_75() async throws {
        let url = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/75_organ.wav")
        let bpm = try await BpmAnalysis().process(url: url)
        #expect(bpm.isMultiple(of: 75))
    }

    @Test func longSong() async throws {
//        let url = URL(fileURLWithPath: "/Users/rf/Music/Music/Media.localized/Music/Aphex Twin/Unknown Album/Actium.mp3")
        let url = URL(fileURLWithPath: "/Users/rf/Music/Music/Media.localized/Music/Aphex Twin/Drukqs Disc 01/07 Drukqs - Disk 01 - bbydhyonchord.mp3")

        let ba = BpmAnalysis()
        await ba.update(eventHandler: { event in
            Log.debug(event)
        })

        let bpm = try await ba.process(url: url)
        #expect(bpm.isMultiple(of: 122))
    }

    @Test func concurrentAccess() async throws {
        let _self = self

        let task1 = Task {
            try await _self.drumloop_60()
        }

        let task2 = Task {
            try await drumloop_200()
        }

        try await task1.value
        try await task2.value
    }
}
