// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKUtils

/// A collection of real-time `AVAudioTime` objects with a hostTime reference for use with player scheduling
public struct LoopScheduler {
    public enum Event {
        case updated(times: [AVAudioTime])
        case complete
    }

    public var eventHandler: ((Event) -> Void)?

    /// just for debugging
    public var label: String = ""

    /// The hostTime that all time schedules will use
    public private(set) var hostTime: UInt64 = mach_absolute_time()

    /// Time schedule of all times
    public private(set) var times: [AVAudioTime] = []

    /// Full duration of the loop
    public private(set) var loopDuration: TimeInterval = 0

    /// Will keep generating new times indefinitely
    public var isInfinite: Bool = true

    public var defaultNumberOfLoops: Int = 10

    public init(label: String = "") {
        self.label = label
    }

    /// Get the next loop time and pop it from the collection
    /// - Returns: next loop time or nil if there are none left
    public mutating func next() -> AVAudioTime? {
        guard times.count > 0 else { return nil }

        let avTime = times.removeFirst()

        // Log.debug("⏰🔁 \(label), scheduled @", avTime.toSeconds(hostTime: hostTime), "now has", times.count, "more iterations left, hostTime", hostTime)

        guard times.count == 0 else {
            return avTime
        }

        guard isInfinite else {
            eventHandler?(.complete)
            return avTime
        }

        let futureTime = loopDuration

        appendSchedule(
            startingIn: avTime.offset(seconds: futureTime).toSeconds(hostTime: hostTime),
            count: defaultNumberOfLoops
        )

        // Log.debug("Generated \(numberOfLoops) more loops", self)

        let times = self.times
        eventHandler?(.updated(times: times))

        return avTime
    }

    public mutating func removeAll() {
        times.removeAll()
    }

    /// Create a loop schedule
    /// - Parameters:
    ///   - startingIn: offset
    ///   - loopDuration: full loop duration
    ///   - hostTime: hostTime reference stored at the creation of this schedule
    ///   - count: how many times to schedule
    public mutating func createSchedule(
        startingIn initialTime: TimeInterval = 0,
        loopDuration: TimeInterval,
        hostTime: UInt64,
        count: Int? = nil
    ) {
        guard loopDuration > 0 else {
            assertionFailure("loopDuration must be > 0")
            return
        }

        removeAll()

        self.hostTime = hostTime
        self.loopDuration = loopDuration

        appendSchedule(startingIn: initialTime, count: count)
    }

    /// Append an existing schedule with additional loop times
    /// - Parameter count: how many loops to append
    private mutating func appendSchedule(
        startingIn initialTime: TimeInterval = 0,
        count: Int? = nil
    ) {
        let count = count ?? defaultNumberOfLoops

        Log.debug("appending", count, "loops, initialTime", initialTime)

        // will grow for each iteration
        var cumulativeTime: TimeInterval = initialTime

        for _ in 0 ..< count {
            let avTime = createTime(seconds: cumulativeTime)
            cumulativeTime += loopDuration

            guard cumulativeTime > 0 else { continue }

            times.append(avTime)
        }

        sort()
    }

    private func createTime(seconds: TimeInterval) -> AVAudioTime {
        guard seconds > 0 else {
            return AVAudioTime(hostTime: hostTime)
        }

        return AVAudioTime.secondsToAudioTime(hostTime: hostTime, time: seconds)
    }

    private mutating func sort() {
        times = times.sorted { lhs, rhs in
            lhs.toSeconds(hostTime: hostTime) <
                rhs.toSeconds(hostTime: hostTime)
        }
    }
}

extension LoopScheduler: CustomStringConvertible {
    public var description: String {
        var timesSummary = ""

        if let first = times.first, let last = times.last {
            timesSummary = "Range: \(first.toSeconds(hostTime: hostTime))...\(last.toSeconds(hostTime: hostTime))"
        }

        return "LoopScheduler \(label) loopDuration: \(loopDuration), hostTime: \(hostTime))" + " [" + timesSummary + "]"
    }
}
