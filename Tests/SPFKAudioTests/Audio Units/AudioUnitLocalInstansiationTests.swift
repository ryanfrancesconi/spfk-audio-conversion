import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKUtils
import Testing

@Suite(.serialized)
final class AudioUnitLocalInstansiationTests {
    let audioComponentDescription = Fader.audioComponentDescription

    // register first so the instansiates will find it all at the same time
    @Test func register() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: audioComponentDescription,
            name: Fader.typeName,
            version: Fader.version
        )
    }

    @Test func instantiateAsync() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let au = try await AVAudioUnit.instantiateLocal(
            with: audioComponentDescription,
            named: Fader.typeName
        )

        #expect(au.auAudioUnit.audioUnitName == Fader.typeName)
    }

    @Test func instantiateAndBlockWithSemaphore() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let au = try AVAudioUnit.instantiateLocalAndBlockWithSemaphore(
            with: audioComponentDescription,
            named: Fader.typeName
        )

        #expect(au.auAudioUnit.audioUnitName == Fader.typeName)
    }

    @Test func instantiateAndBlockRunLoop() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        let au = try AVAudioUnit.instantiateLocalAndBlockRunLoop(
            with: audioComponentDescription,
            named: Fader.typeName
        )

        #expect(au.auAudioUnit.audioUnitName == Fader.typeName)
    }
}
