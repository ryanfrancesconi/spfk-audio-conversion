// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

@preconcurrency import AVFoundation
import Foundation

/// AVAudioUnitComponent collection grouped by Manufacturer
public struct AudioUnitManufacturerCollection: Equatable, Sendable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.componentManufacturer == rhs.componentManufacturer
    }

    public let name: String
    public let componentManufacturer: OSType
    public let audioUnits: [AVAudioUnitComponent]

    public init(
        name: String,
        componentManufacturer: OSType,
        audioUnits: [AVAudioUnitComponent] = [AVAudioUnitComponent]()
    ) {
        self.name = name
        self.componentManufacturer = componentManufacturer
        self.audioUnits = audioUnits
    }
}
