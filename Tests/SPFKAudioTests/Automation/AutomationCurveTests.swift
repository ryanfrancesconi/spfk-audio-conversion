
import AudioToolbox
import Foundation
@testable import SPFKAudio
import SPFKAudioC
import SPFKUtils
import Testing

@Suite(.tags(.automation))
struct AutomationCurveTests {
    @Test func createTaperedSegment() async throws {
        // Curve is: /\
        let points = [
            AutomationPoint(time: 0.019075106002620478, gain: 0.0, selected: false, dBMax: 6),
            AutomationPoint(time: 3.884410354243773, gain: 1.0, selected: false, dBMax: 6),
            AutomationPoint(time: 6.800137064528385, gain: 0.0, selected: true, dBMax: 6),
        ]

        let curve = AutomationCurve(automationPoints: points)
        let events = curve.events

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.0009248927, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.005943559, startTime: 0.019075107, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.01265814, startTime: 0.21907511, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.02071914, startTime: 0.41907513, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.030705478, startTime: 0.6190751, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.043200582, startTime: 0.8190751, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.058793373, startTime: 1.0190752, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.07808004, startTime: 1.2190752, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.10166606, startTime: 1.4190753, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.13016947, startTime: 1.6190753, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.16422543, startTime: 1.8190753, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.20449317, startTime: 2.0190754, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.2516673, startTime: 2.2190754, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.30649626, startTime: 2.4190755, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.36981598, startTime: 2.6190755, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.44261467, startTime: 2.8190756, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.5261766, startTime: 3.0190756, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.62245893, startTime: 3.2190757, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.7354354, startTime: 3.4190757, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.8812173, startTime: 3.6190758, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.584339, startTime: 3.8844104, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.4731614, startTime: 4.08441, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.3877983, startTime: 4.28441, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.3179616, startTime: 4.48441, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.25957137, startTime: 4.6844096, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.21034025, startTime: 4.8844094, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.16871434, startTime: 5.084409, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.13350144, startTime: 5.284409, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.10371025, startTime: 5.484409, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.078470916, startTime: 5.6844087, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.056991555, startTime: 5.8844085, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.03853297, startTime: 6.0844083, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.022393027, startTime: 6.284408, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.007896145, startTime: 6.484408, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 6.6844077, rampDuration: 0.11572933),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
    }

    @Test func replaceAutomationBasic() {
        let curve = AutomationCurve(points: [
            ParameterAutomationPoint(targetValue: 440, startTime: 0, rampDuration: 0.1),
            ParameterAutomationPoint(targetValue: 880, startTime: 1, rampDuration: 0.1),
            ParameterAutomationPoint(targetValue: 440, startTime: 2, rampDuration: 0.1),
        ])

        let events: [(Float, AUValue)] = [(0.5, 100), (1.5, 200)]

        let newCurve = curve.replace(range: 0.25 ... 1.75, withPoints: events)

        let expected = [
            ParameterAutomationPoint(targetValue: 440, startTime: 0.0, rampDuration: 0.1),
            ParameterAutomationPoint(targetValue: 100, startTime: 0.5, rampDuration: 0.01),
            ParameterAutomationPoint(targetValue: 200, startTime: 1.5, rampDuration: 0.01),
            ParameterAutomationPoint(targetValue: 440, startTime: 2.0, rampDuration: 0.1),
        ]

        #expect(newCurve.points == expected)
    }

    @Test func replaceAutomationErase() {
        let curve = AutomationCurve(points: [
            ParameterAutomationPoint(targetValue: 440, startTime: 0, rampDuration: 0.1),
            ParameterAutomationPoint(targetValue: 880, startTime: 1, rampDuration: 0.1),
            ParameterAutomationPoint(targetValue: 440, startTime: 2, rampDuration: 0.1),
        ])

        let events: [(Float, AUValue)] = []

        let newCurve = curve.replace(range: 0 ... 2, withPoints: events)

        #expect(newCurve.points == [])
    }

    @Test func replaceAutomationAdd() {
        let curve = AutomationCurve(points: [])

        let events: [(Float, AUValue)] = [(0.5, 100), (1.5, 200)]

        let newCurve = curve.replace(range: 0 ... 2, withPoints: events)

        let expected = [
            ParameterAutomationPoint(targetValue: 100, startTime: 0.5, rampDuration: 0.01),
            ParameterAutomationPoint(targetValue: 200, startTime: 1.5, rampDuration: 0.01),
        ]

        #expect(newCurve.points == expected)
    }
}
