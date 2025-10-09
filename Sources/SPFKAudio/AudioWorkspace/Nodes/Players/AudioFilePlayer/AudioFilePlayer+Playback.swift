// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

extension AudioFilePlayer {
    /// Update the edit points
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

    public func play() throws {
        guard playerNode.engine?.isRunning == true else {
            throw NSError(description: "Engine isn't running or available - play() canceled for \(audioFile?.url.lastPathComponent ?? "nil")")
        }

        if isPlaying {
            playerNode.stop()
        }

        // plays at the previously scheduled time, nil sigifies now
        playerNode.play(at: nil)

        isPlaying = true
    }

    /// Stop playback and cancel any pending scheduled playback or completion events
    public func stop() {
        guard isPlaying else { return }

        playerNode.stop()
        
        lastScheduledTime = nil
        isPlaying = false
    }
}
