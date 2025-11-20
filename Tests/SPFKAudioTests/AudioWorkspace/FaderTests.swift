import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKUtils
import Testing

@Suite(.serialized)
final class FaderTests {
    public init() async throws {
    }

    @Test func create() async throws {
        let fader = try await Fader(gain: 2)

        #expect(fader.leftGain == 2)
        #expect(fader.rightGain == 2)
        #expect(fader.flipStereo == false)
        #expect(fader.mixToMono == false)
    }
}
