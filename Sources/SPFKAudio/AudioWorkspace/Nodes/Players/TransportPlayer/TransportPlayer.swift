import AppKit
import AVFoundation
import Foundation
import SPFKBase
import SPFKTime

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
            currentURL: currentPlayer?.url,
            duration: duration,
            measure: measure
        )
    }
}

extension TransportPlayer: Mixable {
    public var volume: AUValue {
        get { mixer.volume }
        set { mixer.volume = newValue }
    }

    public var pan: AUValue {
        get { mixer.pan }
        set { mixer.pan = newValue }
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

    public var outputFormat: AVAudioFormat {
        mixer.mixerNode.outputFormat(forBus: 0)
    }

    /// cache a player for each new audio format loaded into the mixer
    private(set) var players: [AVAudioFormat: FilePlayer] = .init()

    /// the player which is actively playing
    private(set) var currentPlayer: FilePlayer?

    public var url: URL? { currentPlayer?.url }

    public var formats: [AVAudioFormat] {
        players.map { $0.key }
    }

    public private(set) var outputTap: AmplitudeTap?

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

    // TODO: the source of truth for all other components rather than copying it everywhere
    public var measure = MusicalMeasureDescription(tempo: 60)

    public var isPlaying: Bool { currentPlayer?.isPlaying == true }

    public private(set) var isLooping: Bool = false

    public var currentTime: TimeInterval {
        get { transportTimer.currentTime }
        set {
            transportTimer.currentTime = newValue
        }
    }

    public var lastScheduledHostTime: UInt64? {
        currentPlayer?.lastScheduledTime?.hostTime
    }

    var restartAfterEventTask: Task<Void, Error>?
    var shouldRestartAfterEvent = false

    /// Will attempt to use a NSScreen display link
    /// - Parameter delegate: needed to connect to the engine
    @MainActor public init(delegate: TransportPlayerDelegate? = nil) throws {
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
        outputTap = AmplitudeTap(mixer.mixerNode, eventHandler: handleAmplitudeEvent)

        self.delegate = delegate

        initialize()
    }

    @MainActor private func initialize() {
        transportTimer.eventHandler = { [weak self] in self?.update(timerEvent: $0) }
        scheduler.eventHandler = { [weak self] in self?.handle(loopEvent: $0) }
    }

    /// To be called on sample rate changes
    public func rebuild() throws {
        outputTap?.dispose()
        outputTap = nil

        for player in players {
            player.value.stop()
            try player.value.detachNodes()
        }

        currentPlayer = nil

        players.removeAll()

        try mixer.detachNodes()

        mixer = MixerWrapper()
        outputTap = AmplitudeTap(mixer.mixerNode, eventHandler: handleAmplitudeEvent)
    }

    private func handleAmplitudeEvent(_ array: [Float]) {
        delegate?.transportPlayer(amplitudeEvent: array)
    }

    public func unload() {
        currentPlayer?.unload()
    }

    public func update(time: TimeInterval) {
        guard !isPlaying else { return }
        currentTime = time.clamped(to: 0 ... duration)
    }

    public func update(looping state: Bool) throws {
        isLooping = state

        if isPlaying {
            try stop()
            try play(time: currentTime)
        }
    }
}

extension TransportPlayer {
    @MainActor public func load(url: URL) async throws {
        try await load(audioFile: try AVAudioFile(forReading: url))
    }

    @MainActor public func load(audioFile: AVAudioFile) async throws {
        guard let delegate else {
            throw NSError(description: "delegate is nil")
        }

        if let currentPlayer {
            guard currentPlayer.audioFile != audioFile else {
                throw NSError(description: "Same audioFile is already loaded")
            }

            currentTime = 0
            delegate.transportPlayer(timerEvent: .time(0))

            currentPlayer.unload()
        }

        var formatPlayer = players[audioFile.processingFormat]

        if formatPlayer == nil {
            // this format hasn't been added yet so do it now
            let newPlayer = FilePlayer()
            try await delegate.connectAndAttach(newPlayer, to: mixer)

            players[audioFile.processingFormat] = newPlayer
            formatPlayer = newPlayer

            Log.debug("(\(outputFormat) Created new player of the file's processingFormat of ", audioFile.processingFormat)
        }

        try formatPlayer?.load(audioFile: audioFile)
        self.currentPlayer = formatPlayer
    }
}
