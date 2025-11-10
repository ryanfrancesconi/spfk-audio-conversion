// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKTime

public enum TransportAction: Equatable {
    case load(url: URL, tempo: Double?)
    case unload

    case play(time: TimeInterval?)
    case stop
    case update(time: TimeInterval)
    case scrub(time: TimeInterval)

    case rewindAll
    case rewind(pulse: MusicalPulse?)
    case forward(pulse: MusicalPulse?)

    case loop(state: Bool)
    case playlistMode(state: Bool)
}
