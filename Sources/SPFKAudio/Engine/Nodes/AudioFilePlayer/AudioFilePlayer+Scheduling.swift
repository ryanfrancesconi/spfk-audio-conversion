// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKUtils

extension AudioFilePlayer {
    var useCompletionHandler: Bool {
        isLooping || completionHandler != nil
    }

    /// Play segments of a file
    func schedule(from startingTime: TimeInterval,
                  to endingTime: TimeInterval = 0) {
        var to = endingTime
        if to == 0 {
            to = editEndTime
        }
        schedule(from: startingTime, to: to, at: nil)
    }

    // AudioRegionView using this +Playback
    @discardableResult
    public func schedule(when scheduledTime: TimeInterval,
                         hostTime: UInt64? = nil) -> AVAudioTime {
        schedule(from: editStartTime,
                 to: editEndTime,
                 when: scheduledTime,
                 hostTime: hostTime)
    }

    @discardableResult
    public func schedule(from startingTime: TimeInterval,
                         to endingTime: TimeInterval,
                         when scheduledTime: TimeInterval,
                         hostTime: UInt64? = nil) -> AVAudioTime {
        let refTime = hostTime ?? mach_absolute_time()

        lastScheduledTimeInterval = scheduledTime

        var avTime: AVAudioTime

        if renderingMode == .offline {
            // needs to be a sample based schedule for offline rendering
            let sampleTime = AVAudioFramePosition(scheduledTime * sampleRate)
            let sampleAVTime = AVAudioTime(hostTime: refTime,
                                           sampleTime: sampleTime,
                                           atRate: sampleRate)
            avTime = sampleAVTime

        } else {
            avTime = AVAudioTime(hostTime: refTime).offset(seconds: scheduledTime)
        }

        schedule(from: startingTime,
                 to: endingTime,
                 at: avTime)

        return avTime
    }

    /// Play using full options. Last in the convenience play chain, all schedule commands will end up here
    func schedule(from startingTime: TimeInterval,
                  to endingTime: TimeInterval,
                  at audioTime: AVAudioTime?) {
        let audioTime = audioTime ?? AVAudioTime.now()

        preroll(from: startingTime, to: endingTime)
        schedulePlayer(at: audioTime)
        pauseTime = nil
    }

    public func schedulePlayer(at audioTime: AVAudioTime) {
        lastScheduledTime = audioTime
        scheduleSegment(at: audioTime)
    }

    // play from disk rather than ram
    private func scheduleSegment(at audioTime: AVAudioTime?) {
        guard let audioFile else { return }

        let startFrame = AVAudioFramePosition(editStartTime * audioFile.fileFormat.sampleRate)
        var endFrame = AVAudioFramePosition(editEndTime * audioFile.fileFormat.sampleRate)

        if endFrame == 0 {
            endFrame = audioFile.length
        }

        let totalFrames = (audioFile.length - startFrame) - (audioFile.length - endFrame)

        guard totalFrames > 0 else {
            Log.error("Unable to schedule file. totalFrames to play: \(totalFrames). audioFile.length: \(audioFile.length)")
            return
        }

        frameCount = AVAudioFrameCount(totalFrames)

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: audioTime,
            completionCallbackType: .dataPlayedBack,
            completionHandler: useCompletionHandler ? handleCallbackComplete : nil
        )

        playerNode.prepare(withFrameCount: frameCount)

        // Log.debug("audioTime", audioTime, "frameCount", frameCount, "isHostTimeValid", audioTime?.isHostTimeValid, "isSampleTimeValid", audioTime?.isSampleTimeValid)
    }

    // MARK: - Completion Handlers

    // Note that a player node should not be stopped from within a completion handler callback because
    // it can deadlock while trying to unschedule previously scheduled buffers.
    func handleCallbackComplete(completionType: AVAudioPlayerNodeCompletionCallbackType) {
        Log.debug("handleCallbackComplete", audioFile?.url.lastPathComponent, "Thread", Thread.current)
        isPlaying = false
        completionHandler?()
    }
}
