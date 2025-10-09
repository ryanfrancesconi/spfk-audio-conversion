import AVFoundation
import Foundation
import SPFKUtils

/// A collection of real-time loop times with a hostTime reference for use with scheduling
public struct ScheduledLoop {
    public static var defaultNumberOfLoops: Int = 20

    // just for debugging
    public var label: String = ""

    /// The hostTime that all time schedules will use
    public private(set) var hostTime: UInt64 = mach_absolute_time()

    /// Time schedule of all times
    public private(set) var times: [TimeInterval] = []

    /// As a loop could be started in the middle of it,
    /// the first duration could be shorter
    public private(set) var firstDuration: TimeInterval?

    /// Full duration of the loop
    public private(set) var duration: TimeInterval = 0

    /// Will keep generating new times indefinitely
    public var isInfinite: Bool = true

    public init(label: String = "") {
        self.label = label
    }

    /// Get the next loop time and pop it from the collection
    /// - Returns: next loop time or nil if there are none left
    public mutating func next() -> AVAudioTime? {
        guard times.count > 0 else { return nil }

        let nextTime = times.removeFirst()

        let avTime = AVAudioTime(hostTime: hostTime).offset(seconds: nextTime)

        if isInfinite, times.count == 1 {
            Log.debug("Generating more loops")
            appendSchedule()
        }

        // Log.debug("⏰🔁 \(label), scheduled @", nextTime, "now has", times.count, "more iterations left, hostTime", hostTime)

        return avTime
    }

    public mutating func removeAll() {
        times.removeAll()
    }

    /// Create a loop schedule
    /// - Parameters:
    ///   - firstDuration: Since you might start mid way through the first loop, the first one can be a different length
    ///   - duration: subsequent full loop duration
    ///   - hostTime: hostTime reference stored at the creation of this schedule
    ///   - count: how many times to schedule
    public mutating func createSchedule(
        firstDuration: TimeInterval? = nil,
        duration: TimeInterval,
        playTime: TimeInterval = 0,
        hostTime: UInt64?,
        count: Int = Self.defaultNumberOfLoops
    ) {
        guard duration > 0 else {
            assertionFailure("duration must be > 0")
            return
        }

        self.hostTime = hostTime ?? mach_absolute_time()
        self.firstDuration = firstDuration
        self.duration = duration

        var count = count

        // will grow for each interation
        var scheduleTime: TimeInterval = 0

        removeAll()

        // firstDuration represents a partial first loop if the playhead
        // is in the middle of a selected area
        if let firstDuration,
           firstDuration > 0,
           firstDuration < duration {
            scheduleTime += firstDuration

            times.append(scheduleTime)
            count -= 1

        } else {
            scheduleTime += (duration + playTime)

            times.append(scheduleTime)
            count -= 1
        }

        for _ in 0 ..< count {
            scheduleTime += duration

            guard scheduleTime > 0 else { continue }

            times.append(scheduleTime)
        }

        sort()
    }

    /// Append an existing schedule with additional loop times
    /// - Parameter count: how many loops to append
    private mutating func appendSchedule(with count: Int = Self.defaultNumberOfLoops) {
        guard times.count > 0 else {
            Log.error("You must create a schedule before appending more")
            return
        }
        guard let lastTime = times.last,
              duration > 0 else { return }

        // set the initial time to the last time in the array
        var scheduleTime = lastTime

        for _ in 0 ..< count {
            scheduleTime += duration
            times.append(scheduleTime)
        }

        sort()
    }

    private mutating func sort() {
        times = times.sorted()
    }
}

extension ScheduledLoop: CustomStringConvertible {
    public var description: String {
        var timesSummary = ""

        if let first = times.first, let last = times.last {
            timesSummary = "Range: \(first)...\(last)"
        }

        return "ScheduledLoop (firstDuration: \(firstDuration?.string ?? "nil"), duration: \(duration), hostTime: \(hostTime))" + " [" + timesSummary + "]"
    }
}
