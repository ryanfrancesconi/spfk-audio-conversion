// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation

public enum TransportAction: Equatable {
    case togglePlay

    case load(audioFile: AVAudioFile)
    case unload

    case play(time: TimeInterval?)
    case stop
    case update(time: TimeInterval)

    case rewindAll
    case rewind
    case forward

    case loop(state: Bool)
    case playlistMode(state: Bool)
}
