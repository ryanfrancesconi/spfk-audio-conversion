// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AudioToolbox
import AVFoundation
import SPFKUtils

extension AudioUnitChain {
    public static func isAvailable(componentDescription: AudioComponentDescription) -> Bool {
        AVAudioUnitComponentManager
            .shared()
            .components(matching: componentDescription)
            .isNotEmpty
    }

    /// Will attempt to create an out of process effect first and if that fails will
    /// return an in process.
    public static func createEffect(
        componentDescription: AudioComponentDescription
    ) async throws -> AVAudioUnit? {
        //
        guard isAvailable(componentDescription: componentDescription) else {
            return nil
        }

        if let value = try? await Self.createEffect(
            componentDescription: componentDescription,
            options: .loadOutOfProcess
        ) {
            return value
        }

        if let value = try await Self.createEffect(
            componentDescription: componentDescription,
            options: .loadInProcess
        ) {
            return value
        }

        return nil
    }

    public static func createEffect(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnit? {
        try await AVAudioUnit.instantiate(
            with: componentDescription,
            options: options
        )
    }

    public static func createInstrument(
        componentDescription: AudioComponentDescription
    ) async throws -> AVAudioUnitMIDIInstrument? {
        try await createEffect(componentDescription: componentDescription) as? AVAudioUnitMIDIInstrument
    }

    public static func createInstrument(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnitMIDIInstrument? {
        try await createEffect(componentDescription: componentDescription, options: options) as? AVAudioUnitMIDIInstrument
    }
}
