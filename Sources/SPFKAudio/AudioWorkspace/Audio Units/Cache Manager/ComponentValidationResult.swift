@preconcurrency import AVFoundation
import AppKit
import SPFKBase

public struct ComponentValidationResult: Sendable {
    public let audioComponentDescription: AudioComponentDescription
    public let component: AVAudioUnitComponent?
    public let name: String
    public let typeName: String
    public let manufacturerName: String
    public let versionString: String
    public let icon: NSImage?

    public var validation: AudioUnitValidator.ValidationResult
    public var isEnabled: Bool

    public var isFormatCompatible: Bool {
        (audioComponentDescription.isEffect || audioComponentDescription.isMusicDevice)
            && component?.supportsStereo == true
    }

    public var supportsMono: Bool {
        component?.supportsMono == true
    }

    public var supportsStereo: Bool {
        component?.supportsStereo == true
    }

    public var description: String {
        if let component {
            "\(component.manufacturerName): \(component.name) (\(component.typeName)), "
                + "More info: \(component.audioComponentDescription.validationCommand)"
        } else {
            audioComponentDescription.validationCommand
        }
    }

    public init(
        audioComponentDescription: AudioComponentDescription,
        component: AVAudioUnitComponent,
        validation: AudioUnitValidator.ValidationResult,
        isEnabled: Bool = true
    ) {
        self.audioComponentDescription = audioComponentDescription
        self.component = component
        self.validation = validation
        self.isEnabled = isEnabled

        name = component.name
        typeName = component.localizedTypeName
        manufacturerName = component.manufacturerName
        versionString = component.versionString
        icon = component.icon
    }

    public init(
        audioComponentDescription: AudioComponentDescription,
        validation: AudioUnitValidator.ValidationResult,
        isEnabled: Bool = true,
        name: String,
        typeName: String,
        manufacturerName: String,
        versionString: String,
        icon: NSImage?
    ) {
        component = nil
        self.audioComponentDescription = audioComponentDescription
        self.validation = validation
        self.isEnabled = isEnabled
        self.name = name
        self.typeName = typeName
        self.manufacturerName = manufacturerName
        self.versionString = versionString
        self.icon = icon
    }
}
