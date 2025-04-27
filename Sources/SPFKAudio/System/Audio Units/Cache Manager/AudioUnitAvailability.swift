import AVFoundation
import Foundation
import SPFKUtils

public protocol AudioUnitAvailability {
    var availableAudioUnitComponents: [AVAudioUnitComponent]? { get }
    var audioUnitManufactererCollection: [AudioUnitManufacturerCollection] { get }
}

extension AudioUnitAvailability {
    public var audioUnitManufactererCollection: [AudioUnitManufacturerCollection] {
        createManufactererCollection()
    }

    public func createManufactererCollection() -> [AudioUnitManufacturerCollection] {
        guard let availableAudioUnitComponents else {
            return []
        }

        var componentManufacturers = availableAudioUnitComponents.map {
            AudioUnitManufacturerCollection(
                name: $0.manufacturerName.trimmed,
                componentManufacturer: $0.audioComponentDescription.componentManufacturer
            )
        }.removingDuplicates()

        // now fill in the audioUnits

        for i in 0 ..< componentManufacturers.count {
            componentManufacturers[i].audioUnits = audioUnits(componentManufacturer: componentManufacturers[i].componentManufacturer)
        }

        componentManufacturers = componentManufacturers.sorted {
            $0.name.standardCompare(with: $1.name)
        }

        return componentManufacturers
    }

    public func audioUnits(componentManufacturer: OSType) -> [AVAudioUnitComponent] {
        availableAudioUnitComponents?.filter {
            $0.audioComponentDescription.componentManufacturer == componentManufacturer

        }.sorted {
            $0.name.standardCompare(with: $1.name)
        } ?? []
    }
}
