// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKBase

extension FilePlayer {
    public func play() throws {
        guard playerNode.engine?.isRunning == true else {
            throw NSError(description: "FilePlayer.play() Engine isn't running or available - play() canceled for \(audioFile?.url.lastPathComponent ?? "nil")")
        }

        if isPlaying {
            playerNode.stop()
        }

        // plays at the previously scheduled time, (nil = now)
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
