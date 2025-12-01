// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKBase

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
            let item = componentManufacturers[i]
            let value = filterComponents(for: item.componentManufacturer)

            componentManufacturers[i] = AudioUnitManufacturerCollection(
                name: item.name,
                componentManufacturer: item.componentManufacturer,
                audioUnits: value
            )
        }

        componentManufacturers = componentManufacturers.sorted {
            $0.name.standardCompare(with: $1.name)
        }

        return componentManufacturers
    }

    // was audioUnits(componentManufacturer:)
    func filterComponents(for componentManufacturer: OSType) -> [AVAudioUnitComponent] {
        availableAudioUnitComponents?.filter {
            $0.audioComponentDescription.componentManufacturer == componentManufacturer

        }.sorted {
            $0.name.standardCompare(with: $1.name)
        } ?? []
    }
}
