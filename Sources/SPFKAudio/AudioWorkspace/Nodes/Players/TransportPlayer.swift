import AppKit
import AVFoundation
import Foundation
import SPFKTime
import SPFKUtils
import SPFKUtilsC

extension TransportPlayer: EngineNode {
    public var inputNode: AVAudioNode? { mixer.inputNode }
    public var outputNode: AVAudioNode? { mixer.outputNode }
}

extension TransportPlayer: TransportStateAccess {
    public var transportState: TransportState {
        TransportState(
            isPlaying: isPlaying,
            isLooping: isLooping,
            currentTime: currentTime
        )
    }
}

/// A player which supports any audio format, realtime sample rate conversion,
/// looping and a built in `DisplayLinkTimer` for screen based refresh events such
/// as tracking a playhead. This class is intended for real time only use such as an
/// audio editor.
public class TransportPlayer {
    public private(set) var mixer: MixerWrapper
    public private(set) var transportTimer: TransportTimer

    public weak var delegate: TransportPlayerDelegate?

    /// cache a player for each new audio format loaded into the mixer
    private var players: [AVAudioFormat: FilePlayer] = .init()

    /// the player which is actively playing
    private var currentPlayer: FilePlayer?

    public var formats: [AVAudioFormat] {
        players.map { $0.key }
    }

    public var duration: TimeInterval { currentPlayer?.duration ?? 0 }
    public var isLoaded: Bool { currentPlayer?.isLoaded == true }

    private var _loopRange: ClosedRange<TimeInterval>?
    public var loopRange: ClosedRange<TimeInterval>? {
        get { _loopRange }
        set {
            _loopRange = newValue?.clamped(to: 0 ... duration)
        }
    }

    public var playbackRange: ClosedRange<TimeInterval> {
        loopRange ?? 0 ... duration
    }

    public private(set) var scheduler = LoopScheduler()

    public var isPlaying: Bool { currentPlayer?.isPlaying == true }

    public private(set) var isLooping: Bool = false

    public var currentTime: TimeInterval {
        get { transportTimer.currentTime }
        set {
            transportTimer.currentTime = newValue
        }
    }

    /// Will attempt to use a NSScreen display link
    /// - Parameter delegate: needed to connect to the engine
    public init(delegate: TransportPlayerDelegate? = nil) throws {
        transportTimer = try TransportTimer()
        mixer = MixerWrapper()
        self.delegate = delegate

        initialize()
    }

    /// Will use a view for the display link
    /// - Parameters:
    ///   - timerView: A NSView to use to sync the timer against
    ///   - delegate: needed to connect to the engine
    @MainActor
    public init(timerView: NSView, delegate: TransportPlayerDelegate? = nil) {
        transportTimer = TransportTimer(on: timerView)
        mixer = MixerWrapper()
        self.delegate = delegate

        initialize()
    }

    private func initialize() {
        transportTimer.eventHandler = { [weak self] event in
            guard let self else { return }

            do {
                try update(timerEvent: event)
            } catch {
                Log.error(error)
            }
        }

        scheduler.eventHandler = { [weak self] in self?.handle(loopEvent: $0) }
    }

    /// To be called on sample rate changes
    public func rebuild() throws {
        for player in players {
            try player.value.detachNodes()
        }

        players.removeAll()

        try mixer.detachNodes()
        mixer = MixerWrapper()
    }

    public func handle(event: AudioEditorEvent) throws {
        Log.debug(event)

        switch event {
        case let .loaded(audioFile: audioFile):
            try load(audioFile: audioFile)

        case .unloaded:
            currentPlayer?.unload()

        case let .play(time: time):
            try play(time: time ?? currentTime)

        case .stop:
            try stop()

        case let .update(time: time):
            guard !isPlaying else { return }

            currentTime = time

        case let .loop(state):
            isLooping = state

            if isPlaying {
                try stop()
                try play(time: currentTime)
            }
        }
    }
}

extension TransportPlayer {
    public func load(url: URL) throws {
        try load(audioFile: try AVAudioFile(forReading: url))
    }

    public func load(audioFile: AVAudioFile) throws {
        guard let delegate else {
            throw NSError(description: "delegate is nil")
        }

        if let currentPlayer {
            guard currentPlayer.audioFile != audioFile else {
                throw NSError(description: "Same audioFile is already loaded")
            }

            currentTime = 0
            currentPlayer.unload()
        }

        var formatPlayer = players[audioFile.processingFormat]

        if formatPlayer == nil {
            // this format hasn't been added yet so do it now
            let newPlayer = FilePlayer()
            try delegate.connectAndAttach(newPlayer, to: mixer)

            players[audioFile.processingFormat] = newPlayer
            formatPlayer = newPlayer

            Log.debug("Created new player of format", audioFile.processingFormat)
        }

        try formatPlayer?.load(audioFile: audioFile)
        self.currentPlayer = formatPlayer
    }
}

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
    public func update(timerEvent event: TransportTimerEvent) throws {
        delegate?.transportPlayer(timerEvent: event)

        guard case let .time(transportTime) = event else { return }

        let loopShim: TimeInterval = isLooping ? 0.01 : 0
        let endTime = loopRange?.upperBound ?? duration

        if transportTime >= endTime - loopShim {
            try handleComplete()
        }
    }

    private func handleComplete() throws {
        let startTime = loopRange?.lowerBound ?? 0

        if isLooping {
            guard let nextTime: AVAudioTime = scheduler.next() else {
                throw NSError(description: "Failed to get next scheduled time")
            }

            // reset the timer to be relative to the next avTime in the schedule
            transportTimer.start(avTime: nextTime.offset(seconds: -startTime))

        } else {
            try stop()

            transportTimer.currentTime = startTime

            if startTime == 0 {
                delegate?.transportPlayer(timerEvent: .complete)
            }

            rewind()
        }
    }

    private func handle(loopEvent event: LoopScheduler.Event) {
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

public protocol TransportPlayerDelegate: AnyObject, AudioEngineConnection {
    func transportPlayer(timerEvent event: TransportTimerEvent)
}
