import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.file))
class SoundClassificationTests: BinTestCase {
    @Test func analyze() async throws {
        let url = TestBundleResources.shared.tabla_wav

        let results = try await SoundClassification.analyze(url: url)

        let identifiers = results?.compactMap { $0.identifier }

        #expect(
            identifiers == ["music", "tabla", "drum", "percussion"]
        )

        Log.debug(results)
    }

    // if a file is too short then there isn't enough chance for the analysis to succeed, so loop it a few time
    // and process that file
    @Test func duplicateInsufficientDataAndAnalyze() async throws {
        let url = TestBundleResources.shared.cowbell_wav

        let tmp = try await AudioTools.createLoopedAudio(input: url, minimumDuration: 6)

        let results = try await SoundClassification.analyze(url: tmp, overlapFactor: 0.5, minimumConfidence: 0.1)

        Log.debug(url.path, "=", results)

        #expect(
            results?.contains(where: { classification in
                classification.identifier == "cowbell"
            }) == true
        )

        #expect(results != nil)
    }
}
