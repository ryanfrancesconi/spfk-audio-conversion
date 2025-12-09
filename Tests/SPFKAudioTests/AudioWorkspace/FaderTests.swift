import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized)
final class FaderTests: TestCaseModel {
    init() async throws {}

    @Test func create() async throws {
        try await wait(sec: 6)
        var fader: Fader? = try await Fader(gain: 2)

        #expect(fader?.leftGain == 2)
        #expect(fader?.rightGain == 2)
        #expect(fader?.flipStereo == false)
        #expect(fader?.mixToMono == false)
        
        fader = nil
        try await wait(sec: 6)

    }
}
