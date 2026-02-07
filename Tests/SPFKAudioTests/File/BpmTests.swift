import AVFoundation
import SPFKAudioC
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.tags(.file))
class BpmTests: TestCaseModel {
    @Test func drumloops() async throws {
        let url1 = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/60_drumloop.wav")
        let url2 = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/110_drumloop.wav")
        let url3 = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/200_drumloop.wav")
        let url4 = URL(fileURLWithPath: "/Users/rf/Downloads/TestResources/bpm/75_organ.wav")

        let bpmAnalysis = BpmAnalysis()
        let bpm1 = try await bpmAnalysis.process(url: url1)
        let bpm2 = try await bpmAnalysis.process(url: url2)
        let bpm3 = try await bpmAnalysis.process(url: url3)
        let bpm4 = try await bpmAnalysis.process(url: url4)

        Log.debug(bpm1, bpm2, bpm3, bpm4)

        #expect(bpm1.isMultiple(of: 60))
        #expect(bpm2.isMultiple(of: 110))
        #expect(bpm3.isMultiple(of: 200))
        #expect(bpm4.isMultiple(of: 75))
    }
    
    @Test func longSong() async throws {
//        let url = URL(fileURLWithPath: "/Users/rf/Music/Music/Media.localized/Music/Aphex Twin/Unknown Album/Actium.mp3")
        let url = URL(fileURLWithPath: "/Users/rf/Music/Music/Media.localized/Music/Aphex Twin/Drukqs Disc 01/07 Drukqs - Disk 01 - bbydhyonchord.mp3")

        let bpmAnalysis = BpmAnalysis()
        let bpm = try await bpmAnalysis.process(url: url)
        
        #expect(bpm.isMultiple(of: 122))

    }
}
