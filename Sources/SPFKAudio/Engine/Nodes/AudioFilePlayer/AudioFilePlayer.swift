// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import OTAtomics
import SPFKUtils

extension AudioFilePlayer: EngineNode {
    public var outputNode: AVAudioNode? { playerNode }

    public func detach() {
        stop()
        engine?.safeDetach(nodes: [playerNode])

        detachNodes()

        audioFile = nil
    }
}

/// An audio player which is associated with a single file
open class AudioFilePlayer: Mixable {
    // MARK: - Nodes

    /// The underlying player node
    @OTAtomicsThreadSafe
    public private(set) var playerNode = AVAudioPlayerNode()

    // MARK: REVIEW

    private var playerTime: TimeInterval {
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            return TimeInterval(playerTime.sampleTime) / playerTime.sampleRate
        }
        return 0
    }

    public internal(set) var lastScheduledTime: AVAudioTime?
    public internal(set) var lastScheduledTimeInterval: TimeInterval?

    public var isScheduled: Bool {
        lastScheduledTime != nil
    }

    // MARK: - Public Properties

    /// Completion handler to be called when Audio is done playing. The handler won't be called if
    /// stop() is called while playing or when looping from a buffer. Requires iOS 11, macOS 10.13.
    public var completionHandler: (() -> Void)?

    /// The internal audio file
    public var audioFile: AVAudioFile?

    public var url: URL? { audioFile?.url }

    /// Will return whether the engine is rendering offline or realtime
    public var renderingMode: AVAudioEngineManualRenderingMode? {
        playerNode.engine?.manualRenderingMode
    }

    /// The duration of the loaded audio file
    public var duration: TimeInterval {
        guard let audioFile else { return 0 }
        return TimeInterval(audioFile.length) / audioFile.fileFormat.sampleRate
    }

    public var editedDuration: TimeInterval {
        (duration - editStartTime) - (duration - editEndTime)
    }

    public var sampleRate: Double {
        playerNode.outputFormat(forBus: 0).sampleRate
    }

    /// - Returns: The total frame count that is being playing.
    /// Differs from the audioFile.length as this will be updated with the edited amount
    /// of frames based on startTime and endTime
    public internal(set) var frameCount: AVAudioFrameCount = 0

    /// - Returns: The current frame while playing. It will return 0 on error.
    public var currentFrame: AVAudioFramePosition {
        guard playerNode.engine != nil,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            Log.error("Error getting currentFrame, was detached:", playerNode.engine == nil)
            return 0
        }
        return playerTime.sampleTime
    }

    /// - Returns: Current time of the player in seconds while playing.
    public var currentTime: TimeInterval {
        let currentDuration = (editEndTime - editStartTime == 0) ? duration : (editEndTime - editStartTime)

        var normalizedPauseTime = 0.0

        if let pauseTime = pauseTime, pauseTime > editStartTime {
            normalizedPauseTime = pauseTime - editStartTime
        }

        let current = editStartTime + normalizedPauseTime + playerTime.truncatingRemainder(dividingBy: currentDuration)

        return current
    }

    public var pauseTime: TimeInterval? {
        didSet {
            isPaused = pauseTime != nil
        }
    }

    // MARK: REVIEW These can be optionals instead of zero

    private var _editStartTime: TimeInterval = 0

    /// Get or set the edit start time of the player.
    public var editStartTime: TimeInterval {
        get { _editStartTime }
        set { _editStartTime = max(0, newValue) }
    }

    private var _editEndTime: TimeInterval = 0

    /// Get or set the edit end time of the player.
    public var editEndTime: TimeInterval {
        get { _editEndTime }

        set {
            var newValue = newValue

            if newValue == 0 {
                newValue = duration
            }

            _editEndTime = min(newValue, duration)
        }
    }

    public var editRange: ClosedRange<TimeInterval> {
        get { editStartTime ... editEndTime }
        set {
            editStartTime = newValue.lowerBound
            editEndTime = newValue.upperBound
        }
    }

    ///  - Returns: the internal processingFormat
    public private(set) var processingFormat: AVAudioFormat?

    // MARK: - Dynamic Options

    /// Volume 0.0 -> ?, default 1.0, > 1 applies gain
    /// This is different than gain
    public var volume: AUValue {
        get { playerNode.volume }
        set {
            playerNode.volume = newValue
        }
    }

    /// Left/Right balance -1.0 -> 1.0, default 0.0
    public var pan: AUValue {
        get { playerNode.pan }
        set {
            playerNode.pan = newValue
        }
    }

    private var lastKnownVolume: AUValue = 1

    /// not really bypassed in this case, just unity volume
    public var isBypassed: Bool = false {
        didSet {
            if isBypassed {
                lastKnownVolume = volume
                volume = 1
            } else {
                volume = lastKnownVolume
            }
        }
    }

    /// Returns if the player is currently paused
    public internal(set) var isPaused: Bool = false

    // MARK: - Public Options

    public internal(set) var isPlaying: Bool = false

    public var isLooping: Bool = false

    // MARK: - Initialization

    public init() {}

    /// Create a player from a URL
    public convenience init(url: URL) throws {
        let avfile = try AVAudioFile(forReading: url)
        self.init(audioFile: avfile)
    }

    /// Create a player from an AVAudioFile.
    public init(audioFile: AVAudioFile) {
        self.audioFile = audioFile
    }

    // MARK: - Loading

    /// Replace the contents of the player with this url. Note that if your processingFormat changes
    /// you should dispose this Player and create a new one instead.
    /// Note, the same URL could be loaded over and over again in the case of renders.
    public func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        try load(audioFile: file)
    }

    /// Load a new audio file into this player. Note that if your processingFormat changes
    /// you should dispose this Player and create a new one instead.
    ///
    /// It's possible this is no longer necessary with updates in macOS - needs testing
    public func load(audioFile: AVAudioFile) throws {
        // check to make sure this isn't the first load. If it is, processingFormat will be nil
        if let format = processingFormat, format != audioFile.processingFormat {
            let message = "Warning: Processing format doesn't match. This file is a different format than the previously loaded one. " +
                "You should make a new Player instance and reconnect. " +
                "load() is only available for files that are the same format."
            throw NSError(description: message)
        }

        self.audioFile = audioFile

        processingFormat = audioFile.processingFormat

        preroll()
    }
}
