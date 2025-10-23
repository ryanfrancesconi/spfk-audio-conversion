// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation

public enum TransportAction: String, CaseIterable, Equatable {
    case play
    case rewindAll
    case rewind
    case forward
    case loop
    case playlistMode // this isn't really a transport action
    
    // forward by step
    // reverse by step
}
