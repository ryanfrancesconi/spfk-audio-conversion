import AppKit
import AVFoundation
import Foundation
import SPFKTime
import SPFKUtils

extension TransportPlayer: EngineNode {
    public var inputNode: AVAudioNode? { mixer.inputNode }
    public var outputNode: AVAudioNode? { mixer.outputNode }
}

extension TransportPlayer: TransportStateAccess {
    public var transportState: TransportState {
        TransportState(
            isPlaying: isPlaying,
            isLooping: isLooping,
            currentTime: currentTime,
            duration: duration
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
    private(set) var players: [AVAudioFormat: FilePlayer] = .init()

    /// the player which is actively playing
    private(set) var currentPlayer: FilePlayer?

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

    var scheduler = LoopScheduler()

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
        transportTimer.eventHandler = { [weak self] in self?.update(timerEvent: $0) }

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

    public func togglePlay() throws {
        try isPlaying ? stop() : play(time: currentTime)
    }

    public func handle(transportAction event: TransportAction) throws {
        Log.debug(event)

        switch event {
        case let .load(audioFile: audioFile):
            try load(audioFile: audioFile)

        case .unload:
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

        default:
            Log.error("unhandled:", event)
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
