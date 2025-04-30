import AudioToolbox
import Foundation
@testable import SPFKAudio
import SPFKUtils
import Testing

struct AutomationPointTests {
    @Test func create() {
        let point1 = AutomationPoint(time: 1, gain: -100, dBMax: 6)
        #expect(point1.dBValue == AutomationPoint.dBMin) // clamp to 0 gain
        #expect(point1.dBRange == AutomationPoint.dBMin ... 6)

        let point2 = AutomationPoint(time: -1, gain: 1, dBMax: 12)
        #expect(point2.time == 0) // clamp to 0
        #expect(point2.gain == 1)
        #expect(point2.dBValue == 0)
        #expect(point2.description == "0 dB")
        #expect(point2.dBRange == AutomationPoint.dBMin ... 12)

        let point3 = AutomationPoint(time: 100, gain: 100, dBMax: 6)
        #expect(point3.time == 100)
        #expect(point3.dBValue == 6) // clamp to dBMax
        #expect(point3.description == "+6.0 dB")
    }

    @Test func update() {
        var point = AutomationPoint(time: 1, gain: 1, dBMax: 6)
        #expect(point.dBValue == 0)

        point.gain = 1.5
        #expect(point.dBValue == 3.52)

        point.gain = 2
        #expect(point.dBValue == 6)
    }

    @Test func createCurve() async throws {
        let points = [
            AutomationPoint(time: 0.019075106002620478, gain: 0.0, selected: false, dBMax: 6.0206003),
            AutomationPoint(time: 3.884410354243773, gain: 1.0, selected: false, dBMax: 6.0206003),
            AutomationPoint(time: 6.800137064528385, gain: 0.0, selected: true, dBMax: 6.0206003),
        ]

        let events = AutomationCurve.createCurve(automationPoints: points)

        Log.debug(events)
    }
}
