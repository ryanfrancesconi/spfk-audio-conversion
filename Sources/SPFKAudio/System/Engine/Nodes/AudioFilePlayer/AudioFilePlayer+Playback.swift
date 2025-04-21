// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

extension AudioFilePlayer {
    /// Sets the edit points and enables the fader if the region
    /// has fade in or out applied to it.
    public func preroll(from startingTime: TimeInterval = 0, to endingTime: TimeInterval = 0) {
        var startingTime = startingTime
        var endingTime = endingTime

        if endingTime == 0 {
            endingTime = duration
        }

        if startingTime > endingTime {
            Log.error("⏰ from", startingTime, "to", endingTime)

            Log.error("startingTime is > than endingTime")
            startingTime = 0
        }

        editStartTime = startingTime
        editEndTime = endingTime
    }

    public func playNode() {
        guard playerNode.engine?.isRunning == true else {
            Log.error("Engine isn't running - aborting playback for", audioFile?.url.lastPathComponent)
            return
        }

        if isPlaying {
            stopNode()
        }

        // play at the previously scheduled time
        playerNode.play(at: nil)

        isPlaying = true
    }

    /// Stop playback and cancel any pending scheduled playback or completion events
    public func stop() {
        guard isPlaying else {
            return
        }

        stopNode()

        isPlaying = false
        pauseTime = nil
    }

    func stopNode() {
        playerNode.stop()
        lastScheduledTime = nil
        lastScheduledTimeInterval = nil
    }

    func pause() {
        pauseTime = currentTime
        stopNode()
        isPaused = true
    }

    func resume() {
        // save the last set startTime as resume will overwrite it
        let previousStartTime = editStartTime

        var time = pauseTime ?? 0

        // bounds check
        if time >= duration {
            time = 0
        }
        // clear the frame count in the player
        stopNode()
        schedule(from: time)
        playNode()

        // restore that startTime as it might be a selection
        editStartTime = previousStartTime
        // restore the pauseTime cleared by play and preserve it by setting _isPaused to false manually
        pauseTime = time
        isPaused = false
    }
}
