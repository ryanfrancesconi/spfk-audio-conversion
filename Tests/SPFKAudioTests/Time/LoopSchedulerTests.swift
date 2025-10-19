import AVFoundation
@testable import SPFKAudio
@testable import SPFKTesting
import SPFKUtils
import Testing

class LoopSchedulerTests {
    @Test func createSchedule() throws {
        var scheduledLoop = LoopScheduler(label: #function)
        let hostTime = mach_absolute_time()
        let loopDuration: TimeInterval = 0.1

        scheduledLoop.createSchedule(
            loopDuration: loopDuration,
            hostTime: hostTime,
            count: 10
        )

        #expect(scheduledLoop.times.count == 10)

        Log.debug("📆", scheduledLoop)

        var previousTime: AVAudioTime = .init(hostTime: hostTime)

        for loop in scheduledLoop.times {
            Log.debug(loop.toSeconds(hostTime: hostTime))

            guard let elapsed = loop.timeIntervalSince(otherTime: previousTime) else {
                continue
            }

            guard elapsed > 0 else { continue }

            #expect(
                elapsed == loopDuration
            )

            previousTime = loop
        }

        #expect(
            scheduledLoop.times.last?.toSeconds(hostTime: hostTime) == 0.9
        )
    }

    @Test func appendSchedule() throws {
        var scheduledLoop = LoopScheduler(label: #function)
        let hostTime = mach_absolute_time()
        let loopDuration: TimeInterval = 0.1
        let count = 10

        scheduledLoop.createSchedule(
            loopDuration: loopDuration,
            hostTime: hostTime,
            count: count
        )

        scheduledLoop.eventHandler = { event in
            Log.debug(event)

            switch event {
            case let .updated(times: times):
                #expect(times.count == count)

            case .complete:
                break
            }
        }

        for i in 1 ... count {
            guard let _ = scheduledLoop.next() else {
                Issue.record("avTime is nil")
                return
            }

            Log.debug(scheduledLoop.times.count)
            
            let index = count - i

            // the times were reloaded with count more
            let value = index == 0 ? count : index

            #expect(scheduledLoop.times.count == value)
        }
    }
}
