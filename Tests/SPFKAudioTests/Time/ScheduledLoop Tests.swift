import AVFoundation
@testable import SPFKAudio
@testable import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized)
class ScheduledLoopTests: BinTestCase {
    @Test func schedule() throws {
        let hostTime = mach_absolute_time()

        let loopDuration: TimeInterval = 0.1

        var scheduledLoop = ScheduledLoop(label: "testSchedule")

        scheduledLoop.createSchedule(firstDuration: 0,
                                     duration: loopDuration,
                                     hostTime: hostTime,
                                     count: 10000)

        Log.debug("📆", scheduledLoop)
        // Log.debug(scheduledLoop.times)

        #expect(scheduledLoop.times.count == 10000)

        let final = try #require(scheduledLoop.times.last)

        #expect(final == 1000.0000000001588)
    }
}
