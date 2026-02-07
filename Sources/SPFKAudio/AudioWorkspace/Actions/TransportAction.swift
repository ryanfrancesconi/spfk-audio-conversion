// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKTime

public enum TransportAction: Equatable, Sendable {
    case load(url: URL)
    case unload
    case play(time: TimeInterval?, hostTime: UInt64?)
    case stop
    case update(time: TimeInterval)
    case scrub(time: TimeInterval)
    case updateTempo(Bpm?)
    case rewindAll
    case rewind(pulse: MusicalPulse?)
    case forward(pulse: MusicalPulse?)
    case loop(state: Bool)
    case playlistMode(state: Bool)
}
