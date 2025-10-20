import AVFoundation
import Foundation
import SPFKTime
import SPFKUtils
import SPFKUtilsC

extension TransportPlayer {
    public func restart() throws {
        guard isPlaying else { return }

        try stop()
        try play(time: currentTime)
    }

    public func play(time: TimeInterval) throws {
        guard let currentPlayer else {
            throw NSError(description: "currentPlayer is nil")
        }

        guard isLoaded else {
            throw NSError(description: "No audio file is loaded")
        }

        var time = time

        if time >= duration {
            Log.error("time \(time) > duration \(duration) - setting to 0")
            time = 0
        }

        let hostTime = mach_absolute_time()

        if isLooping {
            try scheduleLoops(at: time, hostTime: hostTime, count: 5)

        } else {
            try currentPlayer.schedule(from: time, to: playbackRange.upperBound, hostTime: hostTime)
        }

        startTimer(at: time, hostTime: hostTime)

        try play()
    }

    private func play() throws {
        guard let currentPlayer else {
            throw NSError(description: "Player is nil")
        }

        var engineError: Error?

        ExceptionCatcherOperation({
            do {
                try currentPlayer.play()

            } catch {
                Log.error(error)
            }
        }, { exception in
            engineError = NSError(description: exception.debugDescription)

        })

        if let engineError {
            throw engineError
        }
    }

    public func stop() throws {
        guard let currentPlayer else {
            throw NSError(description: "Player is nil")
        }

        guard isLoaded else {
            throw NSError(description: "No audio file is loaded")
        }

        currentPlayer.stop()
        scheduler.removeAll()
        stopTimer()
    }
}

extension TransportPlayer {
    private func scheduleLoops(at time: TimeInterval, hostTime: UInt64, count: Int) throws {
        guard let currentPlayer else {
            throw NSError(description: "currentPlayer is nil")
        }

        let playbackRange = self.playbackRange

        var partialLoopDuration: TimeInterval = 0

        // if the playhead is started inside the current loop range
        if time > playbackRange.lowerBound && time < playbackRange.upperBound {
            partialLoopDuration = playbackRange.upperBound - time
            try currentPlayer.schedule(from: time, to: time + partialLoopDuration, when: 0, hostTime: hostTime)
        }

        let loopDuration = playbackRange.duration

        Log.debug("Play at", time, "loopDuration", loopDuration, "loopRange", loopRange)

        scheduler.createSchedule(
            startingIn: partialLoopDuration,
            loopDuration: loopDuration,
            hostTime: hostTime,
            count: count
        )

        try scheduleAudio(times: scheduler.times)
    }

    private func scheduleAudio(times: [AVAudioTime]) throws {
        guard let currentPlayer else {
            throw NSError(description: "currentPlayer is nil")
        }

        let loopDuration = playbackRange.duration

        for avTime in times {
            try currentPlayer.schedule(
                from: playbackRange.lowerBound,
                to: playbackRange.lowerBound + loopDuration,
                audioTime: avTime
            )
        }
    }

    private func rewind() {
        let startTime = loopRange?.lowerBound ?? 0
        delegate?.transportPlayer(timerEvent: .time(startTime))
    }
}

extension TransportPlayer {
    public func update(timerEvent event: TransportTimerEvent) {
        delegate?.transportPlayer(timerEvent: event)

        guard case let .time(transportTime) = event else { return }

        let loopShim: TimeInterval = isLooping ? 0.01 : 0
        let endTime = loopRange?.upperBound ?? duration

        if transportTime >= endTime - loopShim {
            handleComplete()
        }
    }

    private func handleComplete() {
        let startTime = loopRange?.lowerBound ?? 0

        if isLooping {
            guard let nextTime: AVAudioTime = scheduler.next() else {
                Log.error("Failed to get next scheduled time")
                return
            }

            // reset the timer to be relative to the next avTime in the schedule
            transportTimer.start(avTime: nextTime.offset(seconds: -startTime))

        } else {
            try? stop()

            transportTimer.currentTime = startTime

            if startTime == 0 {
                delegate?.transportPlayer(timerEvent: .complete)
            }

            rewind()
        }
    }

    /// LoopScheduler events
    func handle(loopEvent event: LoopScheduler.Event) {
        do {
            switch event {
            // the loop schedule has changed, schedule the new times in the player
            case let .updated(times: times):
                try scheduleAudio(times: times)

            // the amount of loops requested is complete
            case .complete:
                Task { @MainActor in
                    try stop()
                    rewind()
                }
            }

        } catch {
            Log.error(error)
        }
    }

    private func startTimer(avTime: AVAudioTime) {
        stopTimer()
        transportTimer.start(avTime: avTime)
    }

    private func startTimer(at time: TimeInterval, hostTime: UInt64) {
        stopTimer()
        transportTimer.start(at: time, hostTime: hostTime)
    }

    private func stopTimer() {
        transportTimer.stop()
    }
}
