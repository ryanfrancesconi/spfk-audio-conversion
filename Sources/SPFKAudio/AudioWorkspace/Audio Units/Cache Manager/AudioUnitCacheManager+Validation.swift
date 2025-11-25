// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AEXML
import AudioToolbox
import AVFoundation
import OTCore
import SPFKAudioBase
import SPFKBase

extension AudioUnitCacheManager {
    public static var audioComponentCount: Int {
        var desc = AudioComponentDescription.wildcard
        let count = AudioComponentCount(&desc)
        return count.int
    }

    private static var predicate: NSPredicate {
        let predicate1 = NSPredicate(
            format: "typeName == '\(AVAudioUnitTypeEffect)'", argumentArray: nil
        )

        let predicate2 = NSPredicate(
            format: "typeName == '\(AVAudioUnitTypeMusicEffect)'", argumentArray: nil
        )

        let predicate3 = NSPredicate(
            format: "typeName == '\(AVAudioUnitTypeMusicDevice)'", argumentArray: nil
        )

        let predicate4 = NSPredicate(
            format: "typeName == '\(AVAudioUnitTypeGenerator)'", argumentArray: nil
        )

        return NSCompoundPredicate(
            orPredicateWithSubpredicates: [
                predicate1, predicate2, predicate3, predicate4,
            ]
        )
    }

    /// All the components that this framework can support
    public static var compatibleComponents: [AVAudioUnitComponent] {
        Log.debug("*AU Requesting compatibleComponents from system...")

        let components = AVAudioUnitComponentManager
            .shared()
            .components(matching: predicate)
            .filter {
                $0.audioComponentDescription.componentManufacturer !=
                    kAudioUnitManufacturer_Spongefork
            }

        return components.removingDuplicatesRandomOrdering()
    }

    public static func shouldValidate(audioComponentDescription: AudioComponentDescription) -> Bool {
        let manufacturer = audioComponentDescription.componentManufacturer

        return manufacturer != kAudioUnitManufacturer_Apple &&
            manufacturer != kAudioUnitSubType_SystemOutput &&
            manufacturer != kAudioUnitManufacturer_Spongefork
    }

    public func validate(components: [AVAudioUnitComponent]? = nil) async throws -> [ComponentValidationResult] {
        scanTask = Task<[ComponentValidationResult], Error>(priority: .high) {
            var results = [ComponentValidationResult]()

            let components = components ?? AudioUnitCacheManager.compatibleComponents

            for i in 0 ..< components.count {
                guard !Task.isCancelled else {
                    return results
                }

                let component = components[i]

                let name = component.resolvedName

                Log.debug("Checking", name)

                send(event: .validating(name: name, index: i, count: components.count))

                results.append(
                    validate(component: component)
                )

                // try? await Task.sleep(seconds: 1) // useful for testing
            }

            results = results.sorted(by: { lhs, rhs in
                lhs.manufacturerName < rhs.manufacturerName
            })

            return results
        }

        return try await scanTask?.value ?? []
    }

    private func validate(component: AVAudioUnitComponent) -> ComponentValidationResult {
        guard Self.shouldValidate(audioComponentDescription: component.audioComponentDescription) else {
            Log.debug("* Skipping", component.name)

            return ComponentValidationResult(
                audioComponentDescription: component.audioComponentDescription,
                component: component,
                validation: AudioUnitValidator.ValidationResult(result: .passed)
            )
        }

        let audioComponentDescription = component.audioComponentDescription

        let validationResult = AudioUnitValidator.validate(component: component)

        if validationResult.result != .passed {
            Log.error("*AU validation failed for", component.resolvedName, ". More info run in terminal:", component.audioComponentDescription.validationCommand)
        }

        // HACK: Some special cases that might not be effects or music device specified
        if allowedComponentDescriptions.contains(where: {
            audioComponentDescription.matches($0)
        }) {
            return ComponentValidationResult(
                audioComponentDescription: component.audioComponentDescription,
                component: component,
                validation: AudioUnitValidator.ValidationResult(result: .passed)
            )
        }

        return ComponentValidationResult(
            audioComponentDescription: component.audioComponentDescription,
            component: component,
            validation: validationResult
        )
    }
}
