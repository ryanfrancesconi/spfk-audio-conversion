
import AVFoundation
import Foundation

/// AVAudioUnitComponent grouped by Manufacturer name
public struct AudioUnitManufacturerCollection: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.componentManufacturer == rhs.componentManufacturer
    }

    public var name: String
    public var componentManufacturer: OSType
    public var audioUnits = [AVAudioUnitComponent]()

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
