
import AVFoundation

extension AudioKitAU {
    /// Create an AVAudioUnit for the given description
    /// - Parameter componentDescription: Audio Component Description
    public static func instantiate(componentDescription: AudioComponentDescription, localName: String? = nil) -> AVAudioUnit? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: AVAudioUnit?

        if let localName {
            AUAudioUnit.registerSubclass(
                AudioKitAU.self,
                as: componentDescription,
                name: localName,
                version: .max
            )
        }

        AVAudioUnit.instantiate(
            with: componentDescription,
            options: [.loadInProcess]) { avAudioUnit, _ in
                result = avAudioUnit
                semaphore.signal()
            }

        _ = semaphore.wait(wallTimeout: .distantFuture)

        return result
    }
}
