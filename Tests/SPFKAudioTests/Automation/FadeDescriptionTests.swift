import AudioToolbox
import Foundation
@testable import SPFKAudio
import SPFKAudioC
import SPFKUtils
import Testing

@Suite(.tags(.automation))
struct FadeDescriptionTests {
    // MARK: - in

    @Test func fadeInTruncatingLastPointDuration() throws {
        var desc = RegionFadeDescription()
        desc.maximumGain = 1
        desc.stepResolution = 0.2

        // should be a value that doesn't divide by stepResolution
        desc.inTime = 4.305577
        desc.taper = .audio
        desc.stepResolution = 0.2

        let curve = desc.fadeInCurve()
        let events = try #require(curve?.events)

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
        desc.taper = .linear

        let curve = desc.fadeInCurve()
        let events = try #require(curve?.events)

        #expect(events.count == 2)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 1.0, startTime: 0.0, rampDuration: 1.0),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.fadeInCache?.events)
    }

    @Test func fadeInTaperOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.taper = .audio

        let curve = desc.fadeInCurve()
        let events = try #require(curve?.events)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 0.029227404, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.09485577, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.23173125, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.47973216, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 1.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.fadeInCache?.events)
    }

    @Test func fadeInReverseTaperOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.taper = .reverseAudio

        let curve = desc.fadeInCurve()
        let events = try #require(curve?.events)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 0.55253565, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.7525375, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.87428844, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.94954515, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 1.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.fadeInCache?.events)
    }

    // MARK: - out

    @Test func fadeOutTaperOneSecond() throws {
        var desc = RegionFadeDescription()
        desc.outTime = 1
        desc.segmentDuration = 1
        desc.stepResolution = 0.2
        desc.taper = .audio

        let curve = desc.fadeOutCurve()
        let events = try #require(curve?.events)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 1.0, startTime: -0.02, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.4474643, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.24746248, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.12571156, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.05045481, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 0.8, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.fadeOutCache?.events)
    }

    // test crop
    @Test func fadeOutStartingInsideCurve() throws {
        var desc = RegionFadeDescription()
        desc.outTime = 1
        desc.segmentDuration = 0.8
        desc.taper = .audio

        let curve = desc.fadeOutCurve()
        let events = try #require(curve?.events)

        Log.debug(events)

        let expectedResult = [
            AutomationEvent(targetValue: 0.4474643, startTime: -0.02, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.24746248, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.12571156, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.05045481, startTime: 0.40000004, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 0.6, rampDuration: 0.19999999),
        ]

        #expect(events.count == expectedResult.count)
        #expect(events == expectedResult)
        #expect(events == desc.fadeOutCache?.events)
    }

    // MARK: - cache

    @Test func fadeCache() throws {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.outTime = 1
        desc.segmentDuration = 2
        desc.taper = .audio

        let curveIn = desc.fadeInCurve()
        let curveOut = desc.fadeOutCurve()

        #expect(desc.fadeInCache != nil)
        #expect(desc.fadeInCache == curveIn)

        #expect(desc.fadeInCache != nil)
        #expect(desc.fadeOutCache == curveOut)

        desc.inTime = 0
        desc.outTime = 0
        #expect(desc.fadeInCache == nil)
        #expect(desc.fadeOutCache == nil)
    }
}
