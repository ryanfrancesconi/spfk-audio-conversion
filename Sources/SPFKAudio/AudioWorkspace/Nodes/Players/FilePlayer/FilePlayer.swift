// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAUHost
import SPFKBase

/// An audio player which is associated with a single file
open class FilePlayer: AudioEngineNodeAU, Mixable, @unchecked Sendable {
    // MARK: - Node

    public var avAudioNode: AVAudioNode { playerNode }

    /// The underlying player node
    private(set) var playerNode = AVAudioPlayerNode()

    public internal(set) var lastScheduledTime: AVAudioTime?

    public var isScheduled: Bool {
        lastScheduledTime != nil
    }

    /// The internal audio file
    public private(set) var audioFile: AVAudioFile?

    public var url: URL? { audioFile?.url }

    /// Will return whether the engine is rendering offline or realtime
    public var renderingMode: AVAudioEngineManualRenderingMode? {
        playerNode.engine?.manualRenderingMode
    }

    public var sampleRate: Double? {
        audioFile?.fileFormat.sampleRate
    }

    /// - Returns: The current frame while playing. It will return 0 on error.
    public var currentFrame: AVAudioFramePosition? {
        guard let engine,
              engine.isRunning,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else {
            Log.error("Error getting currentFrame, was detached:", playerNode.engine == nil)
            return nil
        }

        return max(0, playerTime.sampleTime)
    }

    /// - Returns: Current time of the player in seconds while playing.
    public var currentTime: TimeInterval? {
        guard let sampleRate, let currentFrame, let playbackRange else { return nil }

        let playerTime = currentFrame.double / sampleRate

        return playerTime + playbackRange.lowerBound
    }

    /// The duration of the loaded audio file
    public var duration: TimeInterval? {
        audioFile?.duration
    }

    public var editedDuration: TimeInterval? {
        playbackRange?.duration
    }

    /// The start time and end time of the audio to be played.
    /// IE 1 ... 3, starts at 1 second and ends on 3. editedDuration == 2
    public private(set) var playbackRange: ClosedRange<TimeInterval>?

    public func updateTimeRange(
        from startingTime: TimeInterval? = nil,
        to endingTime: TimeInterval? = nil
    ) throws {
        guard let duration else {
            throw NSError(file: #file, function: #function, description: "No audio file is loaded")
        }

        let startingTime = startingTime ?? 0
        let endingTime = endingTime ?? duration

        let lowerBound = max(0, startingTime)
        let upperBound = min(duration, endingTime)

        guard lowerBound < upperBound else {
            throw NSError(file: #file, function: #function, description: "invalid edit range \(lowerBound)...\(upperBound)")
        }

        playbackRange = lowerBound ... upperBound
    }

    ///  - Returns: the internal processingFormat
    public private(set) var processingFormat: AVAudioFormat?

    // MARK: -

    /// Volume 0.0 -> ?, default 1.0, > 1 applies gain
    public var volume: Float {
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

    // MARK: - Public Options

    public internal(set) var isPlaying: Bool = false

    public var isLoaded: Bool { audioFile != nil }

    // MARK: - Initialization

    public init() {}

    /// Create a player from a URL
    public convenience init(url: URL) throws {
        try self.init(audioFile: AVAudioFile(forReading: url))
    }

    /// Create a player from an AVAudioFile.
    public init(audioFile: AVAudioFile) {
        self.audioFile = audioFile
    }

    // MARK: - Loading

    /// Replace the contents of the player with this url. Note that if your processingFormat changes
    /// you should dispose this Player and create a new one instead.
    public func load(url: URL) throws {
        try load(audioFile: AVAudioFile(forReading: url))
    }

    /// Load a new audio file into this player. Note that if your processingFormat changes
    /// you should dispose this Player and create a new one instead.
    ///
    /// It's possible this is no longer necessary with updates in macOS - needs testing
    public func load(audioFile: AVAudioFile) throws {
        // check to make sure this isn't the first load. If it is, processingFormat will be nil
        if let processingFormat, processingFormat != audioFile.processingFormat {
            let message = "Warning: Processing format doesn't match. This file is a different format than the previously loaded one. " +
                "You should make a new Player instance and reconnect. " +
                "load() is only available for files that are the same format."
            throw NSError(file: #file, function: #function, description: message)
        }

        self.audioFile = audioFile

        processingFormat = audioFile.processingFormat
        playbackRange = 0 ... audioFile.duration
    }

    public func unload() {
        if isPlaying {
            stop()
        }

        audioFile = nil
        playbackRange = nil
    }
}

extension FilePlayer: AudioEngineNode {
    public var outputNode: AVAudioNode? { playerNode }

    public func detachNodes() throws {
        unload()

        try detachIONodes()
    }
}
