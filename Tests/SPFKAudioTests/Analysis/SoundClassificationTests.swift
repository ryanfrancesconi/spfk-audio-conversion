import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized)
class SoundClassificationTests: BinTestCase {
    @Test func knownClassifications() throws {
        let list = try SoundClassification.knownClassificationsForVersion1().sorted()
        Swift.print(list)
    }

    @Test func recognize1() async throws {
        let url = BundleResources.shared.tabla_wav

        let results = try await SoundClassification.analyze(url: url)

        let identifiers = results?.compactMap { $0.identifier }

        #expect(
            identifiers == ["music", "tabla", "drum", "percussion"]
        )

        Log.debug(results)
    }

    // if a file is too short then there isn't enough chance for the analysis to succeed, so loop it a few time
    // and process that file
    @Test func duplicateInsufficientData() async throws {
        let url = BundleResources.shared.cowbell_wav

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

// MARK: - development

extension SoundClassificationTests {
    @Test func recognize2() async throws {
        let urls = [
            "/Volumes/ADD2/Import Tests/untitled folder/Untitled 2.wav",
            "/Volumes/ADD2/Import Tests/untitled folder/Untitled 3.wav",
            "/Volumes/ADD2/Import Tests/untitled folder/roar.wav",

        ].map { URL(fileURLWithPath: $0) }

        for url in urls {
            guard url.exists else { continue }
            let results = try await SoundClassification.analyze(url: url, overlapFactor: 0.5, minimumConfidence: 0.1)
            Log.debug(url.path, "=", results)
        }
    }
}
