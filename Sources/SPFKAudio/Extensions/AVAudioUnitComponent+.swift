// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation

extension AVAudioUnitComponent {
    public var supportsStereo: Bool {
        supportsNumberInputChannels(2, outputChannels: 2)
    }

    public var supportsMono: Bool {
        supportsNumberInputChannels(1, outputChannels: 1)
    }

    public var resolvedName: String {
        if name == "" {
            return manufacturerName + " " + typeName
        }

        return name
    }

    public static func component(matching componentDescription: AudioComponentDescription) -> AVAudioUnitComponent? {
        AVAudioUnitComponentManager
            .shared()
            .components(matching: componentDescription)
            .compactMap { $0 }
            .first
    }
}
