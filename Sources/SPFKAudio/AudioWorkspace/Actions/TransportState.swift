// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKTime

public struct TransportState {
    public var isPlaying: Bool
    public var isLooping: Bool
    public var currentTime: TimeInterval
    public var currentURL: URL?
    public var duration: TimeInterval
    public var measure: MusicalMeasureDescription

    public init(
        isPlaying: Bool = false,
        isLooping: Bool = false,
        currentTime: TimeInterval = 0,
        currentURL: URL? = nil,
        duration: TimeInterval = 0,
        measure: MusicalMeasureDescription = .init(timeSignature: ._4_4, tempo: 60)
    ) {
        self.isPlaying = isPlaying
        self.isLooping = isLooping
        self.currentTime = currentTime
        self.currentURL = currentURL
        self.duration = duration
        self.measure = measure
    }
}

@MainActor
public protocol TransportStateAccess {
    var transportState: TransportState { get }
}
