
import AVFoundation

extension AVAudioUnit {
    public static func instantiateLocal(
        with componentDescription: AudioComponentDescription,
        named name: String? = nil,
        version: UInt32? = nil
    ) async throws -> AVAudioUnit {
        //
        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: componentDescription,
            name: name ?? "Local AU",
            version: version ?? 1
        )

        return try await instantiate(
            with: componentDescription,
            options: .loadInProcess
        )
    }

    /// Legacy non async support
    public static func instantiateLocal(
        with componentDescription: AudioComponentDescription,
        named name: String? = nil,
        version: UInt32? = nil,
        completionHandler: @escaping (AVAudioUnit?, (any Error)?) -> Void
    ) {
        //
        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: componentDescription,
            name: name ?? "Local AU",
            version: version ?? 1
        )

        instantiate(
            with: componentDescription,
            options: .loadInProcess,
            completionHandler: completionHandler
        )
    }
}

// MARK: - test blocking non-async versions

extension AVAudioUnit {
    /// Create an AVAudioUnit for the given description
    /// - Parameter componentDescription: Audio Component Description
    static func instantiateLocalAndBlockWithSemaphore(
        with componentDescription: AudioComponentDescription,
        named name: String? = nil,
        version: UInt32? = nil
    ) throws -> AVAudioUnit {
        //
        let semaphore = DispatchSemaphore(value: 0)
        var result: AVAudioUnit?
        var resultError: Error?

        instantiateLocal(
            with: componentDescription,
            named: name,
            version: version
        ) { avAudioUnit, error in
            result = avAudioUnit
            resultError = error
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(
            wallTimeout: .now() + .seconds(5)
        )

        guard timeoutResult == .success else {
            throw NSError(description: "Failed to create an AVAudioUnit for \(componentDescription)")
        }

        if let resultError {
            throw resultError
        }

        guard let result else {
            throw NSError(description: "AVAudioUnit is nil for \(componentDescription)")
        }

        return result
    }

    /// Here only for testing AudioKit v6 func - it isn't as performant or safe
    static func instantiateLocalAndBlockRunLoop(
        with componentDescription: AudioComponentDescription,
        named name: String? = nil,
        version: UInt32? = nil
    ) throws -> AVAudioUnit {
        var result: AVAudioUnit?
        var resultError: Error?
        let runLoop = RunLoop.current

        instantiateLocal(
            with: componentDescription,
            named: name,
            version: version
        ) { avAudioUnit, error in
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
