import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKBase
import Testing

@Suite(.tags(.development))
class SoundClassificationDevelopmentTests: BinTestCase {
    @Test func analyze() async throws {
        let urls = [
            "/Volumes/ADD2/Import Tests/untitled folder/Untitled 2.wav",
            "/Volumes/ADD2/Import Tests/untitled folder/Untitled 3.wav",
            "/Volumes/ADD2/Import Tests/untitled folder/roar.wav",

        ].compactMap {
            URL(fileURLWithPath: $0)
        }
        .filter { $0.exists }

        for url in urls {
            let results = try await SoundClassification.analyze(url: url, overlapFactor: 0.5, minimumConfidence: 0.1)
            Log.debug(url.path, "=", results)
        }
    }

    @Test func knownClassificationsForVersion1() throws {
        let list = try SoundClassification.knownClassificationsForVersion1().sorted()
        Log.debug(list)
    }
}
