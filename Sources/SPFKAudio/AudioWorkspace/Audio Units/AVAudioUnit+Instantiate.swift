
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
