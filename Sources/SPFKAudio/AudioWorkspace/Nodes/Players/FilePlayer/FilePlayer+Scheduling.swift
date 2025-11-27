// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

extension FilePlayer {
    public func schedule(
        from startingTime: TimeInterval? = nil,
        to endingTime: TimeInterval? = nil,
        when scheduledTime: TimeInterval = 0,
        hostTime: UInt64? = nil
    ) throws {
        let hostTime = hostTime ?? mach_absolute_time()

        guard let audioTime: AVAudioTime = audioTime(scheduledTime: scheduledTime, hostTime: hostTime) else {
            throw NSError(description: "Failed to create scheduled time")
        }

        try schedule(from: startingTime, to: endingTime, audioTime: audioTime)
    }

    public func schedule(
        from startingTime: TimeInterval? = nil,
        to endingTime: TimeInterval? = nil,
        audioTime: AVAudioTime
    ) throws {
        try updateTimeRange(from: startingTime, to: endingTime)
        try scheduleSegment(at: audioTime)
    }

    /// a segment must be scheduled before you can play
    private func scheduleSegment(at audioTime: AVAudioTime?) throws {
        guard let audioFile else {
            throw NSError(description: "No audio file is loaded")
        }

        guard let playbackRange else {
            throw NSError(description: "invalid edit range")
        }

        lastScheduledTime = audioTime

        let sampleRate: Double = audioFile.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(playbackRange.lowerBound * sampleRate)
        let endFrame = AVAudioFramePosition(playbackRange.upperBound * sampleRate)
        let totalFrames = endFrame - startFrame

        guard totalFrames > 0 else {
            throw NSError(description: "Unable to schedule file. totalFrames to play: \(totalFrames). audioFile.length: \(audioFile.length)")
        }

        let frameCount = AVAudioFrameCount(totalFrames)

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: audioTime,
            completionCallbackType: .dataPlayedBack,
            completionHandler: nil // completionHandler != nil ? handleCallbackComplete : nil
        )

        playerNode.prepare(withFrameCount: frameCount)
    }

    // MARK: - Helpers

    private func audioTime(scheduledTime: TimeInterval, hostTime: UInt64) -> AVAudioTime? {
        if renderingMode == .offline {
            guard let sampleRate else { return nil }

            // needs to be a sample based AVAudioTime for offline rendering
            let sampleTime = AVAudioFramePosition(scheduledTime * sampleRate)

            let sampleAVTime = AVAudioTime(
                hostTime: hostTime,
                sampleTime: sampleTime,
                atRate: sampleRate
            )

            return sampleAVTime

        } else {
            return AVAudioTime(hostTime: hostTime).offset(seconds: scheduledTime)
        }
    }
}
