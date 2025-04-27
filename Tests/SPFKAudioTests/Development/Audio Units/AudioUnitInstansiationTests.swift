import AVFoundation
import Foundation
import Numerics
@testable import SPFKAudio
import SPFKMetadata
import SPFKTesting
import SPFKUtils
import Testing

/**
 AudioUnitInstansiationTests.swift:register() took 0.0069062916591065004 seconds.
 AudioUnitInstansiationTests.swift:instantiateAsync() took 0.0007763750036247075 seconds.
 AudioUnitInstansiationTests.swift:instantiateAndBlockWithSemaphore() took 0.00013404166384134442 seconds.
 AudioUnitInstansiationTests.swift:instantiateAndBlockRunLoop() took 0.012704916662187316 seconds.
 */

@Suite(.serialized, .tags(.development))
final class AudioUnitInstansiationTests {
    let audioComponentDescription = Fader.audioComponentDescription

    @Test func register() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        AUAudioUnit.registerSubclass(
            AudioKitAU.self,
            as: audioComponentDescription,
            name: "test",
            version: .max
        )
    }

    @Test func instantiateAsync() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        _ = try await AVAudioUnit.instantiateLocal(
            componentDescription: audioComponentDescription,
            named: "test"
        )
    }

    @Test func instantiateAndBlockWithSemaphore() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        _ = try AVAudioUnit.instantiateLocalAndBlockWithSemaphore(
            componentDescription: audioComponentDescription,
            named: "test"
        )
    }

    @Test func instantiateAndBlockRunLoop() async throws {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        _ = try AVAudioUnit.instantiateLocalAndBlockRunLoop(
            componentDescription: audioComponentDescription,
            named: "test"
        )
    }
}
