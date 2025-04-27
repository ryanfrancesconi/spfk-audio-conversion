// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

extension AudioUnitChain {
    @discardableResult
    public func load(chainDescription: [AudioEffectDescription]) async throws -> [Error?] {
        //
        guard chainDescription.isNotEmpty else {
            try await removeEffects()
            return []
        }

        var errors = [Error?](repeating: nil, count: await data.insertCount)

        for desc in chainDescription {
            guard let index = desc.index, errors.indices.contains(index) else {
                Log.error("invalid index in", desc)
                continue
            }

            errors[index] = try await insertAudioUnit(effectDescription: desc, at: index)

            try await bypassEffect(at: index, state: desc.isBypassed, reconnect: false)
        }

        try await connect()

        return errors
    }

    // returns on global thread
    public func insertAudioUnit(
        effectDescription: AudioEffectDescription,
        at index: Int
    ) async throws -> Error? {
        guard let componentDescription = effectDescription.componentDescription else {
            throw NSError(description: "Failed to create AudioComponentDescription")
        }

        let audioUnit = try await insertAudioUnit(componentDescription: componentDescription, at: index)

        if let fullState = effectDescription.fullStateDictionary {
            audioUnit.auAudioUnit.fullState = fullState
        }

        return nil
    }

    /// Create the Audio Unit at the specified index of the chain

    @discardableResult
    public func insertAudioUnit(
        componentDescription: AudioComponentDescription,
        at index: Int
    ) async throws -> AVAudioUnit {
        try await data.check(index: index)

        let ctype = componentDescription.componentType

        var audioUnit: AVAudioUnit?

        switch ctype {
        case kAudioUnitType_Effect, kAudioUnitType_MusicEffect, kAudioUnitType_FormatConverter:
            if let value = try? await Self.createEffect(
                componentDescription: componentDescription
            ) {
                audioUnit = value
            }

        case kAudioUnitType_MusicDevice, kAudioUnitType_Generator:
            if let value = try? await Self.createInstrument(
                componentDescription: componentDescription
            ) {
                audioUnit = value
            }

        default:
            throw NSError(description: "Unsupported component type of \(ctype) \(ctype.fourCharCodeToString() ?? "????")")
        }

        guard let audioUnit else {
            throw NSError(description: "Failed to create audio unit from \(componentDescription)")
        }

        try await handleAudioUnitCreated(index: index, audioUnit: audioUnit)

        return audioUnit
    }

    @MainActor
    private func handleAudioUnitCreated(index: Int, audioUnit: AVAudioUnit) async throws {
        try await data.check(index: index)

        // will throw an error if no inputs
        if audioUnit.numberOfInputs > 0,
           audioUnit.inputFormat(forBus: 0).channelCount == 1 {
            Log.error("\(audioUnit) is a Mono effect. Please select a stereo version of it.")
            return
        }

        let desc = AudioUnitDescription(avAudioUnit: audioUnit)

        try await update(
            audioUnit: desc,
            at: index
        )

        Log.debug("* Audio Unit created at index \(index): \(desc.name ?? "")")
    }

    private func update(audioUnit: AudioUnitDescription, at index: Int) async throws {
        if try await data.effect(at: index) != nil {
            try await removeEffect(at: index, reconnectChain: true, sendEvent: true)
            try await Task.sleep(seconds: 0.5)
        }

        try await data.assign(audioUnitDescription: audioUnit, to: index)
    }
}
