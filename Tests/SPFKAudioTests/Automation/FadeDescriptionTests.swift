import AudioToolbox
import Foundation
@testable import SPFKAudio
import SPFKAudioC
import SPFKUtils
import Testing

struct FadeDescriptionTests {
    @Test func fadeInTaperOneSecond() {
        var desc = RegionFadeDescription()
        desc.inTime = 1
        desc.inTaper = AudioTaper.taper.in

        let events = desc.fadeInCurve()

        #expect(events.count == 6)

        Log.debug(events)

        let result = [
            AutomationEvent(targetValue: 0.0, startTime: -0.1, rampDuration: 0.0),
            AutomationEvent(targetValue: 0.029206177, startTime: 0.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.09482492, startTime: 0.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.23171553, startTime: 0.4, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.47976443, startTime: 0.6, rampDuration: 0.2),
            AutomationEvent(targetValue: 1.0, startTime: 0.8, rampDuration: 0.2),
        ]

        #expect(events[0] == result[0])

        #expect(events == desc.inEvents)
    }

    @Test func fadeOutTaperOneSecond() {
        var desc = RegionFadeDescription()
        desc.outTime = 1
        desc.outTaper = AudioTaper.taper.out

        let events = desc.fadeOutCurve(duration: 5)

        #expect(events.count == 7)

        Log.debug(events)

        let result = [
            AutomationEvent(targetValue: 1.0, startTime: 3.98, rampDuration: 0.02),
            AutomationEvent(targetValue: 0.5116574, startTime: 4.0, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.21566933, startTime: 4.2, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.063824415, startTime: 4.3999996, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.007961512, startTime: 4.5999994, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.0, startTime: 4.799999, rampDuration: 0.2),
            AutomationEvent(targetValue: 0.007961273, startTime: 4.999999, rampDuration: 0.2),
        ]

        #expect(events == result)
        #expect(events == desc.outEvents)
    }
}
