
import SPFKUtils
import AppKit
import AVFoundation

public struct ComponentValidationResult {
    public var audioComponentDescription: AudioComponentDescription

    public var component: AVAudioUnitComponent?

    public var validation: AudioUnitValidator.ValidationResult

    public var isEnabled: Bool = true

    public var isFormatCompatible: Bool {
        (audioComponentDescription.isEffect || audioComponentDescription.isMusicDevice) && component?.supportsStereo == true
    }

    public var supportsMono: Bool {
        component?.supportsMono == true
    }

    public var supportsStereo: Bool {
        component?.supportsStereo == true
    }

    public var name: String = ""

    public var typeName: String = ""

    public var manufacturerName: String = ""

    public var versionString: String = ""

    public var icon: NSImage?

    public var description: String {
        if let component = component {
            return "\(component.manufacturerName): \(component.name) (\(component.typeName)), " +
                "More info: \(component.audioComponentDescription.validationCommand)"
        } else {
            return audioComponentDescription.validationCommand
        }
    }

    public init(audioComponentDescription: AudioComponentDescription,
                component: AVAudioUnitComponent?,
                validation: AudioUnitValidator.ValidationResult,
                isEnabled: Bool = true) {
        self.audioComponentDescription = audioComponentDescription
        self.component = component
        self.validation = validation
        self.isEnabled = isEnabled

        if let component {
            name = component.name
            typeName = component.localizedTypeName
            manufacturerName = component.manufacturerName
            versionString = component.versionString
            icon = component.icon
        }
    }
}
