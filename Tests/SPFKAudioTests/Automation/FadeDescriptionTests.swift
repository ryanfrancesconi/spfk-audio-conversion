import AudioToolbox
import Foundation
@testable import SPFKAudio
import SPFKAudioC
import SPFKUtils
import Testing

struct FadeDescriptionTests {
    // MARK: - in

    @Test func fadeInTruncatingLastPoint() throws {
        var desc = RegionFadeDescription()
        desc.maximumGain = 1
        desc.stepResolution = 0.2

        // should be a value that doesn't divide by stepResolution
        desc.inTime = 4.305577
        desc.inTaper = 3
        desc.inSkew = 1
        desc.stepResolution = 0.2

        let events = desc.fadeInCurve()

        let firstPoint = try #require(events.first)
        let lastPoint = try #require(events.last)

        Log.debug(firstPoint, lastPoint)

        #expect(events.count == 23)
        #expect(firstPoint == AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0))
        #expect(lastPoint == AutomationEvent(targetValue: 1.0, startTime: 4.2000003, rampDuration: 0.105576515))
    }

    @Test func fadeInLinearOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.inTaper = LinearTaper.taper.in

        let events = desc.fadeInCurve()
        #expect(events.count == 6)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 0.19999999, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.39999998, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.6, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.8000001, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 1.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.inEvents)
    }

    @Test func fadeInTaperOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.inTaper = AudioTaper.taper.in

        let events = desc.fadeInCurve()

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 0.029206177, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.09482492, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.23171553, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.47976443, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 1.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.inEvents)
    }

    @Test func fadeInReverseTaperOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.inTaper = ReverseAudioTaper.taper.in

        let events = desc.fadeInCurve()

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 0.5528915, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.7527821, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.87441194, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.9495829, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 1.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.inEvents)
    }

    // MARK: - out

    @Test func fadeOutTaperOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.outTime = 1
        desc.stepResolution = 0.2
        desc.outTaper = AudioTaper.taper.out

        let events = desc.fadeOutCurve(segmentDuration: 1)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 1.0, startTime: -0.02, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.51165706, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.21566892, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.06382412, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.007961452, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.outEvents)
    }

    @Test func fadeOutStartingInsideCurve() throws {
        var desc = RegionFadeDescription()
        desc.outTime = 1
        desc.outTaper = AudioTaper.taper.out

        let events = desc.fadeOutCurve(segmentDuration: 0.8)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.51165706, startTime: -0.02, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.21566892, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.06382412, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.007961452, startTime: 0.40000004, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 0.6, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.outEvents)
    }
}
