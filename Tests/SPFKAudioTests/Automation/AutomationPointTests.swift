import AudioToolbox
import Foundation
@testable import SPFKAudio
@testable import SPFKAudioC
import SPFKUtils
import Testing

@Suite(.tags(.automation))
struct AutomationPointTests {
    @Test func create() {
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

    @Test func createCurve() async throws {
        // Curve is: /\
        let points = [
            AutomationPoint(time: 0.019075106002620478, gain: 0.0, selected: false, dBMax: 6.0206003),
            AutomationPoint(time: 3.884410354243773, gain: 1.0, selected: false, dBMax: 6.0206003),
            AutomationPoint(time: 6.800137064528385, gain: 0.0, selected: true, dBMax: 6.0206003),
        ]

        let curve = AutomationCurve(automationPoints: points)
        let events = curve.events

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.0009248927, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.0059377546, startTime: 0.019075107, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.012646589, startTime: 0.21907511, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.020702163, startTime: 0.41907513, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.030683639, startTime: 0.6190751, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.043174695, startTime: 0.8190751, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.058764502, startTime: 1.0190752, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.07804948, startTime: 1.2190752, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.10163532, startTime: 1.4190753, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.13014029, startTime: 1.6190753, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.16419974, startTime: 1.8190753, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.20447305, startTime: 2.0190754, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.25165498, startTime: 2.2190754, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.30649412, startTime: 2.4190755, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.3698263, startTime: 2.6190755, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.4426396, startTime: 2.8190756, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.5262178, startTime: 3.0190756, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.6225171, startTime: 3.2190757, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.73550797, startTime: 3.4190757, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.88128626, startTime: 3.6190758, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.58405524, startTime: 3.8844104, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.47286767, startTime: 4.08441, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.3875172, startTime: 4.28441, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.3177045, startTime: 4.48441, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.2593448, startTime: 4.6844096, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.21014757, startTime: 4.8844094, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.16855654, startTime: 5.084409, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.13337752, startTime: 5.284409, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.10361773, startTime: 5.484409, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.078405954, startTime: 5.6844087, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.056949496, startTime: 5.8844085, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.038508665, startTime: 6.0844083, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.022381285, startTime: 6.284408, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.007892711, startTime: 6.484408, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 6.6844077, rampDuration: 0.11572933),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
    }
}
