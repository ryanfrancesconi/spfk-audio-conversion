// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKUtils

extension AudioFilePlayer {
    @discardableResult
    public func schedule(
        from startingTime: TimeInterval? = nil,
        to endingTime: TimeInterval? = nil,
        when scheduledTime: TimeInterval = 0,
        hostTime: UInt64? = nil
    ) throws -> AVAudioTime {
        let hostTime = hostTime ?? mach_absolute_time()
        let audioTime: AVAudioTime = audioTime(scheduledTime: scheduledTime, hostTime: hostTime)
        lastScheduledTimeInterval = scheduledTime

        try schedule(from: startingTime, to: endingTime, audioTime: audioTime)
        return audioTime
    }

    public func schedule(
        from startingTime: TimeInterval? = nil,
        to endingTime: TimeInterval? = nil,
        audioTime: AVAudioTime
    ) throws {
        let startingTime = startingTime ?? editStartTime
        let endingTime = endingTime ?? editEndTime

        lastScheduledTime = audioTime
        preroll(from: startingTime, to: endingTime)

        try scheduleSegment(at: audioTime)
    }

    /// a segment must be scheduled before you can play
    public func scheduleSegment(at audioTime: AVAudioTime?) throws {
        guard let audioFile else {
            throw NSError(description: "No audio file is loaded")
        }

        let sampleRate: Double = audioFile.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(editStartTime * sampleRate)
        var endFrame = AVAudioFramePosition(editEndTime * sampleRate)

        if endFrame == 0 {
            endFrame = audioFile.length
        }

        let totalFrames = (audioFile.length - startFrame) - (audioFile.length - endFrame)

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
            completionHandler: completionHandler != nil ? handleCallbackComplete : nil
        )

        playerNode.prepare(withFrameCount: frameCount)
    }

    // MARK: - Helpers

    private func audioTime(scheduledTime: TimeInterval, hostTime: UInt64) -> AVAudioTime {
        if renderingMode == .offline {
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

    // Note that a player node should not be stopped from within a completion handler callback because
    // it can deadlock while trying to unschedule previously scheduled buffers.
    private func handleCallbackComplete(completionType: AVAudioPlayerNodeCompletionCallbackType) {
        isPlaying = false
        completionHandler?()
    }
}
