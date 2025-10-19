// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation

public protocol TransportStateAccess {
    var transportState: TransportState { get }
}

public struct TransportState {
    public var isPlaying: Bool
    public var isLooping: Bool
    public var currentTime: TimeInterval

    public init(isPlaying: Bool = false, isLooping: Bool = false, currentTime: TimeInterval = 0) {
        self.isPlaying = isPlaying
        self.isLooping = isLooping
        self.currentTime = currentTime
    }
}
