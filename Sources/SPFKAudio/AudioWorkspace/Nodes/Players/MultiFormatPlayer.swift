import AppKit
import AVFoundation
import Foundation
import SPFKTime
import SPFKUtils
import SPFKUtilsC

extension MultiFormatPlayer: EngineNode {
    public var inputNode: AVAudioNode? { mixer.inputNode }
    public var outputNode: AVAudioNode? { mixer.outputNode }
}

public class MultiFormatPlayer {
    public private(set) var mixer: MixerWrapper

    public weak var delegate: MultiFormatPlayerDelegate?

    // create a player for each new audio format loaded into the mixer
    private var players: [AVAudioFormat: AudioFilePlayer] = .init()

    public var formats: [AVAudioFormat] {
        players.map { $0.key }
    }

    public private(set) var currentPlayer: AudioFilePlayer?

    public var duration: TimeInterval { currentPlayer?.duration ?? 0 }
    public var isPlaying: Bool { currentPlayer?.isPlaying == true }
    public var isLoaded: Bool { currentPlayer?.isLoaded == true }

    public var isLooping: Bool = false

    private var _loopRange: ClosedRange<TimeInterval>?
    public var loopRange: ClosedRange<TimeInterval>? {
        get { _loopRange }
        set {
            _loopRange = newValue?.clamped(to: 0 ... duration)
        }
    }

    public private(set) var scheduledLoop = ScheduledLoop()

    public private(set) var transportTimer: TransportTimer

    public var currentTime: TimeInterval { transportTimer.currentTime }

    @MainActor
    public init(timerView: NSView, delegate: MultiFormatPlayerDelegate? = nil) {
        mixer = MixerWrapper()
        self.delegate = delegate

        transportTimer = TransportTimer(on: timerView)

        transportTimer.eventHandler = { [weak self] event in
            guard let self else { return }

            do {
                try update(timerEvent: event)
            } catch {
                Log.error(error)
            }
        }
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
            try play(time: time)

        case .stop:
            try stop()

        case let .loop(state):
            isLooping = state

            if isPlaying {
                try stop()
                try play(time: currentTime)
            }
        }
    }

    public func load(audioFile: AVAudioFile) throws {
        guard let delegate else {
            throw NSError(description: "delegate is nil")
        }

        if let currentPlayer {
            currentPlayer.unload()
        }

        var formatPlayer = players[audioFile.processingFormat]

        if formatPlayer == nil {
            // this format hasn't been added yet so do it now
            let newPlayer = AudioFilePlayer()
            try delegate.connectAndAttach(newPlayer, to: mixer)

            players[audioFile.processingFormat] = newPlayer
            formatPlayer = newPlayer

            Log.debug("Created new player of format", audioFile.processingFormat)
        }

        try formatPlayer?.load(audioFile: audioFile)
        self.currentPlayer = formatPlayer
    }

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
            throw NSError(description: " No audio file is loaded")
        }

        var time = time

        if time >= duration {
            time = 0
        }

        let hostTime = mach_absolute_time()

        Log.debug("Play at", time, "loopRange", loopRange, "isLooping", isLooping)

        if isLooping {
            let loopRange = loopRange ?? 0 ... duration

            var firstDuration: TimeInterval?

            if time < loopRange.upperBound {
                firstDuration = loopRange.upperBound - time
            }

            let loopDuration = loopRange.upperBound - loopRange.lowerBound

            scheduledLoop.createSchedule(
                firstDuration: firstDuration,
                duration: loopDuration,
                hostTime: hostTime
            )
        }

        let endTime = loopRange?.upperBound ?? duration

        try currentPlayer.schedule(from: time, to: endTime, hostTime: hostTime)

        startTimer(at: time, hostTime: hostTime)

        try play()
    }

    private func play() throws {
        guard let currentPlayer else {
            throw NSError(description: " Player is nil")
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
            throw NSError(description: " Player is nil")
        }

        guard isLoaded else {
            throw NSError(description: " No audio file is loaded")
        }

        currentPlayer.stop()
        scheduledLoop.removeAll()

        stopTimer()
    }
}

extension MultiFormatPlayer {
    public func update(timerEvent event: TransportTimerEvent) throws {
        delegate?.multiFormatPlayer(timerEvent: event)

        guard case let .time(transportTime) = event else { return }

        let loopShim: TimeInterval = isLooping ? 0.001 : 0
        let endTime = loopRange?.upperBound ?? duration

        if transportTime >= endTime - loopShim {
            try handleComplete()
        }
    }

    private func handleComplete() throws {
        guard let currentPlayer else { return }

        let startTime = loopRange?.lowerBound ?? 0

        if isLooping {
            guard let avTime = scheduledLoop.next() else {
                throw NSError(description: " Didn't get valid time for scheduledLoop.next()")
            }

            let endTime = loopRange?.upperBound ?? duration
            currentPlayer.preroll(from: startTime, to: endTime)

            try currentPlayer.scheduleSegment(at: avTime)

            let now = mach_absolute_time()
            startTimer(at: startTime, hostTime: now)

        } else {
            try stop()
            delegate?.multiFormatPlayer(timerEvent: .time(startTime)) // rewind
        }
    }

    private func startTimer(at time: TimeInterval, hostTime: UInt64) {
        stopTimer()
        transportTimer.start(at: time, hostTime: hostTime)
    }

    private func stopTimer() {
        transportTimer.stop()
    }
}

public protocol MultiFormatPlayerDelegate: AnyObject, AudioEngineConnection {
    func multiFormatPlayer(timerEvent event: TransportTimerEvent)
}
