import AudioToolbox
import Foundation
@testable import SPFKAudio
@testable import SPFKAudioC
import SPFKUtils
import Testing

@Suite(.tags(.automation))
struct AutomationPointTests {
    @Test func create1() {
        let point = AutomationPoint(time: 0, gain: 1.5, dBMax: 6)

        #expect(
            point.dBRange.upperBound.isApproximatelyEqual(
                to: point.gainRange.upperBound.dBValue,
                absoluteTolerance: 0.1
            )
        )
        
        #expect(point.gain == 1.5)
        #expect(point.dBValue == 3.52)
        #expect(point.label == "+3.5 dB")
    }

    @Test func create2() {
        let point1 = AutomationPoint(time: 1, gain: -100, dBMax: 6)
        #expect(point1.dBValue == AutomationPoint.dBMin) // clamp to 0 gain
        #expect(point1.dBRange == AutomationPoint.dBMin ... 6)

        let point2 = AutomationPoint(time: -1, gain: 1, dBMax: 12)
        #expect(point2.time == 0) // clamp to 0
        #expect(point2.gain == 1)
        #expect(point2.dBValue == 0)
        #expect(point2.label == "0 dB")
        #expect(point2.dBRange == AutomationPoint.dBMin ... 12)

        let point3 = AutomationPoint(time: 100, gain: 100, dBMax: 6)
        #expect(point3.time == 100)
        #expect(point3.dBValue == 6) // clamp to dBMax
        #expect(point3.label == "+6.0 dB")
    }

    @Test func update() {
        var point = AutomationPoint(time: 1, gain: 1, dBMax: 6)
        #expect(point.dBValue == 0)

        point.gain = 1.5
        #expect(point.dBValue == 3.52)

        point.gain = 2
        #expect(point.dBValue == 6)
    }
}
