
import AVFoundation

extension AVAudioUnit {
    public static func instantiateLocal(
        componentDescription: AudioComponentDescription,
        named name: String? = nil
    ) async throws -> AVAudioUnit {
        //
        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: componentDescription,
            name: name ?? "Local AU",
            version: .max
        )

        return try await AVAudioUnit.instantiate(
            with: componentDescription,
            options: [.loadInProcess]
        )
    }
}

// MARK: - test blocking versions

extension AVAudioUnit {
    /// Create an AVAudioUnit for the given description
    /// - Parameter componentDescription: Audio Component Description
    static func instantiateLocalAndBlockWithSemaphore(
        componentDescription: AudioComponentDescription,
        named name: String? = nil
    ) throws -> AVAudioUnit {
        //
        let semaphore = DispatchSemaphore(value: 0)
        var result: AVAudioUnit?
        var resultError: Error?

        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: componentDescription,
            name: name ?? "Local AU",
            version: .max
        )

        AVAudioUnit.instantiate(
            with: componentDescription,
            options: [.loadInProcess]) { avAudioUnit, error in
                result = avAudioUnit
                resultError = error
                semaphore.signal()
            }

        _ = semaphore.wait(wallTimeout: .distantFuture)

        if let resultError {
            throw resultError
        }

        guard let result else {
            throw NSError(description: "The Audio Unit is nil for \(componentDescription)")
        }

        return result
    }

    /// Here only for testing AudioKit v6 func - it isn't performant
    static func instantiateLocalAndBlockRunLoop(
        componentDescription: AudioComponentDescription,
        named name: String? = nil
    ) throws -> AVAudioUnit {
        //
        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: componentDescription,
            name: "Local AU",
            version: .max
        )

        var result: AVAudioUnit?
        var resultError: Error?

        let runLoop = RunLoop.current

        AVAudioUnit.instantiate(with: componentDescription) { avAudioUnit, error in

            runLoop.perform {
                result = avAudioUnit
                resultError = error
            }
        }

        while result == nil {
            runLoop.run(until: .now + 0.01)
        }

        if let resultError {
            throw resultError
        }

        guard let result else {
            throw NSError(description: "The Audio Unit is nil for \(componentDescription)")
        }

        return result
    }
}
