import AVFoundation
@testable import SPFKAudio
@testable import SPFKTesting
import SPFKUtils
import Testing

class ScheduledLoopTests {
    @Test func schedule() throws {
        var scheduledLoop = ScheduledLoop(label: "testSchedule")

        let hostTime = mach_absolute_time()
        let loopDuration: TimeInterval = 0.1

        scheduledLoop.createSchedule(
            firstDuration: 0,
            duration: loopDuration,
            hostTime: hostTime,
            count: 10000
        )

        Log.debug("📆", scheduledLoop)

        #expect(scheduledLoop.times.count == 10000)

        let final = try #require(scheduledLoop.times.last)

        #expect(final == 1000.0000000001588)
    }
}
