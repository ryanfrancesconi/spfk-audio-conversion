import Numerics
@testable import SPFKAudio
import SPFKMetadata
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
final class LoudnessTests: BinTestCase {
    @Test func testMeasureLoudness() async throws {
        let url = BundleResources.shared.tabla_wav

        let loudness = try await Loudness.analyze(url: url)

        let range = try #require(loudness.loudnessRange)

        #expect(loudness.lufs == -24.1)
        #expect(range == 1.4275153988048004)
        #expect(loudness.truePeak == -0.1)
    }

    /// Will also test looped audio
    @Test func testMeasureLoudnessShortFile() async throws {
        let url = BundleResources.shared.cowbell_wav

        let loudness = try await Loudness.analyze(url: url)

        #expect(loudness.lufs == -29.5)
    }

    @Test func testAverageLoudness() async throws {
        let targetLevel: Double = -23

        let urls = [BundleResources.shared.mp3_id3, BundleResources.shared.tabla_wav, BundleResources.shared.cowbell_wav]

        var values = [LoudnessDescription]()

        for url in urls {
            guard let value = try? await Loudness.analyze(url: url) else { continue }

            values.append(value)

            Log.debug("Change to target is", targetLevel - (value.lufs ?? 0))
        }

        let lufs = try #require(LoudnessDescription.averageLoudness(from: values).lufs)

        Log.debug("🔊 values:", values)
        Log.debug("🔊 average:", lufs)

        #expect(
            lufs.isApproximatelyEqual(to: -25.26, relativeTolerance: 0.001)
        )
    }
}
