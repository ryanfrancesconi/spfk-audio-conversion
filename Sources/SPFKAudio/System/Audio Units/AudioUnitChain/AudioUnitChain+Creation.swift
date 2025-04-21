
import AEXML
import AppKit
import AudioToolbox
import AVFoundation
import SPFKUtils

extension AudioUnitChain {
    static func isAvailable(componentDescription: AudioComponentDescription) -> Bool {
        AVAudioUnitComponentManager
            .shared()
            .components(matching: componentDescription)
            .isNotEmpty
    }

    static func createEffect(
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
            Log.debug("AU: Returning out of process:", value.name)
            return value
        }

        if let value = try await Self.createEffect(
            componentDescription: componentDescription,
            options: .loadInProcess
        ) {
            Log.debug("AU: Returning IN process:", value.name)
            return value
        }

        return nil
    }

    static func createEffect(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnit? {
        let avAudioUnit = try await AVAudioUnitEffect.instantiate(
            with: componentDescription,
            options: options
        )

        return avAudioUnit
    }

    static func createInstrument(
        componentDescription: AudioComponentDescription
    ) async throws -> AVAudioUnitMIDIInstrument? {
        if let value = try? await Self.createInstrument(
            componentDescription: componentDescription,
            options: .loadOutOfProcess
        ) {
            Log.debug("AU: Returning out of process:", value.name)
            return value
        }

        if let value = try await Self.createInstrument(
            componentDescription: componentDescription,
            options: .loadInProcess
        ) {
            Log.debug("AU: Returning IN process:", value.name)
            return value
        }

        return nil
    }

    static func createInstrument(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnitMIDIInstrument? {
        try await AVAudioUnitMIDIInstrument.instantiate(
            with: componentDescription,
            options: options
        ) as? AVAudioUnitMIDIInstrument
    }
}

// MARK: - Legacy completion handler versions

extension AudioUnitChain {
    public typealias EffectCallback = (AVAudioUnit?) -> Void
    public typealias InstrumentCallback = (AVAudioUnitMIDIInstrument?) -> Void
    public typealias MIDIProcessorCallback = (AVAudioUnit?) -> Void

    static func createEffectLegacyWrapped(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnit? {
        try await withCheckedThrowingContinuation { continuation in
            createEffect(componentDescription: componentDescription, options: options) { avAudioUnit in
                continuation.resume(returning: avAudioUnit)
            }
        }
    }

    /// Asynchronously create the AU, then call the
    /// supplied completion handler when the operation is complete.
    static func createEffect(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = [.loadInProcess],
        completionHandler: @escaping EffectCallback
    ) {
        AVAudioUnitEffect.instantiate(
            with: componentDescription,
            options: options
        ) { avAudioUnit, error in
            if let error {
                Log.error(error)
                completionHandler(nil)
                return
            }

            completionHandler(avAudioUnit)
        }
    }

    /// Asynchronously create the AU, then call the
    /// supplied completion handler when the operation is complete.
    static func createInstrument(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = [.loadInProcess],
        completionHandler: @escaping InstrumentCallback
    ) {
        guard isAvailable(componentDescription: componentDescription) else {
            Log.error("Didn't find audio unit", componentDescription)
            completionHandler(nil)
            return
        }

        AVAudioUnitMIDIInstrument.instantiate(
            with: componentDescription,
            options: options
        ) { avAudioUnit, error in
            if let error {
                Log.error(error)
                completionHandler(nil)
                return
            }
            completionHandler(avAudioUnit as? AVAudioUnitMIDIInstrument)
        }
    }

    /// Asynchronously create the AU, then call the
    /// supplied completion handler when the operation is complete.
    static func createMIDIProcessor(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = [.loadInProcess],
        completionHandler: @escaping MIDIProcessorCallback
    ) {
        guard isAvailable(componentDescription: componentDescription) else {
            Log.error("Didn't find audio unit", componentDescription)
            completionHandler(nil)
            return
        }

        AVAudioUnit.instantiate(
            with: componentDescription,
            options: options
        ) { avAudioUnit, error in
            if let error {
                Log.error(error)
                completionHandler(nil)
                return
            }
            completionHandler(avAudioUnit)
        }
    }
}
