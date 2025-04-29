import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.development))
final class AudioUnitInstansiationTests {
    let audioComponentDescription = Fader.audioComponentDescription

    // register first so the instansiates will find it all at the same time
    @Test func register() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: audioComponentDescription,
            name: Fader.typeName,
            version: .max
        )
    }

    @Test func instantiateAsync() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        _ = try await AVAudioUnit.instantiateLocal(
            componentDescription: audioComponentDescription,
            named: Fader.typeName
        )
    }

    @Test func instantiateAndBlockWithSemaphore() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        _ = try AVAudioUnit.instantiateLocalAndBlockWithSemaphore(
            componentDescription: audioComponentDescription,
            named: Fader.typeName
        )
        
        Log.debug("done")
    }

    @Test func instantiateAndBlockRunLoop() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        _ = try AVAudioUnit.instantiateLocalAndBlockRunLoop(
            componentDescription: audioComponentDescription,
            named: Fader.typeName
        )
    }
}
