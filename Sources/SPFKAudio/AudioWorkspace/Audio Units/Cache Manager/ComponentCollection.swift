// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import SPFKAudioBase
import SPFKAudioC
import SPFKUtils

public struct ComponentCollection {
    public var isEmpty: Bool {
        validationResults.isEmpty
    }

    public private(set) var validationResults = [ComponentValidationResult]()

    public var passedEffects: [ComponentValidationResult] {
        validationResults.filter {
            $0.validation.result == .passed && $0.isFormatCompatible

        }.sorted { lhs, rhs in
            lhs.description < rhs.description
        }
    }

    public var unavailableEffects: [ComponentValidationResult] {
        validationResults.filter {
            !$0.isFormatCompatible
        }.sorted { lhs, rhs in
            lhs.description < rhs.description
        }
    }

    public var failedEffects: [ComponentValidationResult] {
        validationResults.filter {
            $0.validation.result != .passed
        }.sorted { lhs, rhs in
            lhs.description < rhs.description
        }
    }

    public var validationDescription: String {
        func flatten(collection: [ComponentValidationResult], title: String) -> String {
            var text = ""
            text += "\(title)\n\n"

            text += collection.map(\.description).sorted().joined(separator: "\n")
            return text
        }

        var text = HardwareInfo.description

        let passedEffects = passedEffects
        let failedEffects = failedEffects
        let unavailableEffects = unavailableEffects

        if passedEffects.isNotEmpty {
            let title = "\(passedEffects.count) Audio Unit\(passedEffects.pluralString) \(passedEffects.count == 1 ? "is" : "are") compatible:"
            text += flatten(collection: passedEffects, title: title)
            text += "\n\n"
        }

        if failedEffects.isNotEmpty {
            let unableToOpen = failedEffects.filter { $0.validation.result != .failed }
            let failed = failedEffects.filter { $0.validation.result == .failed }

            if failed.isNotEmpty {
                text += flatten(collection: failed, title: "These Audio Units didn't pass validation:")
                text += "\n\n"
            }

            if unableToOpen.isNotEmpty {
                text += flatten(collection: unableToOpen, title: "Unable to open:")
                text += "\n\n"
            }
        }

        if unavailableEffects.isNotEmpty {
            let incompatibleEffects = unavailableEffects.filter(\.supportsStereo)

            if incompatibleEffects.isNotEmpty {
                text += flatten(collection: incompatibleEffects, title: "These Audio Units aren't supported:")
                text += "\n\n"
            }

            let monoEffects = unavailableEffects.filter { $0.supportsMono && !$0.supportsStereo }

            if monoEffects.isNotEmpty {
                text += flatten(collection: monoEffects, title: "Currently only supporing stereo Audio Units. These are mono:")
                text += "\n\n"
            }
        }

        return text
    }

    public var effectTypes: [String] {
        validationResults.compactMap {
            $0.component?.typeName
        }.removingDuplicatesRandomOrdering().sorted()
    }

    public init(results: [ComponentValidationResult]) {
        validationResults = results.filter {
            $0.audioComponentDescription.componentManufacturer !=
                kAudioUnitManufacturer_Spongefork
        }
    }

    public mutating func update(audioComponentDescription: AudioComponentDescription, isEnabled: Bool) {
        for i in 0 ..< validationResults.count
            where validationResults[i].audioComponentDescription.matches(audioComponentDescription)
        {
            //
            validationResults[i].isEnabled = isEnabled
        }
    }

    public mutating func update(result: ComponentValidationResult) {
        for i in 0 ..< validationResults.count
            where validationResults[i].audioComponentDescription.matches(result.audioComponentDescription)
        {
            //
            validationResults[i].validation = result.validation
        }
    }

    public mutating func update(from collection: ComponentCollection) {
        for item in collection.validationResults {
            update(audioComponentDescription: item.audioComponentDescription, isEnabled: item.isEnabled)
        }
    }
}
