import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKUtils
import Testing

@Suite(.serialized)
final class AudioUnitLocalInstansiationTests {
    let audioComponentDescription: AudioComponentDescription

    public init() async throws {
        audioComponentDescription = try await Fader().audioComponentDescription
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
