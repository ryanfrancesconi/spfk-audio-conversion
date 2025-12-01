import AVFoundation
import Foundation
import SPFKBase
import SPFKBaseC
import SPFKTime

extension TransportPlayer {
    public func restart() throws {
        try stop()
        try play(time: nil)
    }

    public func play(time: TimeInterval?, hostTime: UInt64? = nil) throws {
        guard let engine = mixer.engine else {
            throw NSError(description: "Engine is nil")
        }

        guard engine.isRunning else {
            throw NSError(description: "Engine isn't running")
        }

        guard let currentPlayer else {
            throw NSError(description: "play: currentPlayer is nil")
        }

        guard isLoaded else {
            throw NSError(description: "No audio file is loaded")
        }

        var time = time ?? currentTime

        if time >= duration {
            Log.error("time \(time) > duration \(duration) - setting to 0")
            time = 0
        }

        if !playbackRange.contains(time) {
            time = playbackRange.lowerBound
        }

        let hostTime = hostTime ?? mach_absolute_time()

        if isLooping {
            try scheduleLoops(at: time, hostTime: hostTime)

        } else {
            try currentPlayer.schedule(from: time, to: playbackRange.upperBound, hostTime: hostTime)
        }

        startTimer(at: time, hostTime: hostTime)

        try playAndCatchException()
    }

    private func playAndCatchException() throws {
        guard let currentPlayer else {
            throw NSError(description: "Player is nil")
        }

        try ExceptionTrap.withThrowing { [currentPlayer] in
            try currentPlayer.play()
        }
    }

    public func stop() throws {
        defer {
            scheduler.removeAll()
            stopTimer()
        }

        guard let currentPlayer else {
            throw NSError(description: "Player is nil")
        }

        guard isLoaded else {
            throw NSError(description: "No audio file is loaded")
        }

        guard isPlaying else {
            return
        }

        currentPlayer.stop()
    }
}

extension TransportPlayer {
    private func scheduleLoops(at time: TimeInterval, hostTime: UInt64) throws {
        guard let currentPlayer else {
            throw NSError(description: "scheduleLoops: currentPlayer is nil")
        }

        let playbackRange = playbackRange

        var partialLoopDuration: TimeInterval = 0

        // if the playhead is started inside the current loop range
        if time > playbackRange.lowerBound, time < playbackRange.upperBound {
            partialLoopDuration = playbackRange.upperBound - time
            try currentPlayer.schedule(from: time, to: time + partialLoopDuration, when: 0, hostTime: hostTime)
        }

        let loopDuration = playbackRange.duration

        Log.debug("Play at", time, "loopDuration", loopDuration, "loopRange", loopRange)

        scheduler.createSchedule(
            startingIn: partialLoopDuration,
            loopDuration: loopDuration,
            hostTime: hostTime,
        )

        try scheduleAudio(times: scheduler.times)
    }

    private func scheduleAudio(times: [AVAudioTime]) throws {
        guard let currentPlayer else {
            throw NSError(description: ": currentPlayer is nil")
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
        do {
            let startTime = loopRange?.lowerBound ?? 0

            if isLooping {
                guard let nextTime: AVAudioTime = scheduler.next() else {
                    Log.error("Failed to get next scheduled time")
                    return
                }

                // reset the timer to be relative to the next avTime in the schedule
                transportTimer.start(avTime: nextTime.offset(seconds: -startTime))

            } else {
                try stop()

                transportTimer.currentTime = startTime

                if startTime == 0 {
                    delegate?.transportPlayer(timerEvent: .complete)
                }

                try rewindAll()
            }
        } catch {
            Log.error(error)
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
                try stop()
                try rewindAll()
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
        outputTap?.start()
    }

    private func stopTimer() {
        transportTimer.stop()
        outputTap?.stop()
    }
}

extension TransportPlayer {
    public func rewindAll() throws {
        let wasPlaying = isPlaying

        if wasPlaying {
            try stop()
        }

        let startTime = loopRange?.lowerBound ?? 0
        currentTime = startTime

        delegate?.transportPlayer(timerEvent: .time(startTime))

        if wasPlaying {
            try play(time: startTime)
        }
    }

    @MainActor public func rewind(by pulse: MusicalPulse?) throws {
        if let loopRange, loopRange.contains(currentTime) {
            try move(to: loopRange.lowerBound)
            return
        }

        try move(by: stepInterval(for: pulse, direction: .backward))
    }

    @MainActor public func forward(by pulse: MusicalPulse?) throws {
        try move(by: stepInterval(for: pulse, direction: .forward))
    }

    @MainActor private func move(by stepTime: TimeInterval) throws {
        let time = (currentTime + stepTime).clamped(to: 0 ... duration)
        try move(to: time)
    }

    @MainActor private func move(to time: TimeInterval) throws {
        if isPlaying {
            shouldRestartAfterEvent = true
            try stop()
        }

        currentTime = time
        delegate?.transportPlayer(timerEvent: .time(time))

        restartAfterEventTask?.cancel()
        restartAfterEventTask = Task<Void, Error> {
            try await Task.sleep(seconds: 0.2)
            try Task.checkCancellation()

            if shouldRestartAfterEvent {
                shouldRestartAfterEvent = false

                Task { @MainActor in
                    // this needs to be an event sent out if another player needs to sync to this one
                    delegate?.transportPlayer(shouldRestartAtTime: time)
                }
            }
        }
    }

    private func stepInterval(for pulse: MusicalPulse?, direction: MovementDirection) -> TimeInterval {
        let value = MusicalMeasureDescription.timeToNearest(
            pulse: pulse,
            measure: measure,
            at: currentTime,
            direction: direction
        )

        // generate a test expect of this event
        // Swift.print("#expect(MusicalMeasureDescription.timeToNearest(pulse: .\(pulse.rawValue), measure: \(measure.description), at: \(currentTime), direction: .\(direction)) == \(value))")

        return value
    }
}
