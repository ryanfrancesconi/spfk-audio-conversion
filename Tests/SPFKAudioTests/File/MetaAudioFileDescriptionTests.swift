import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.file))
class MetaAudioFileDescriptionTests {
    @Test func codable() async throws {
        let url = BundleResources.shared.mp3_id3
        let mafDescription = try MetaAudioFileDescription(parsing: url)

        #expect(mafDescription.tagProperties?.tags.count == 28)

        let data = try #require(mafDescription.dataRepresentation)

        Log.debug(mafDescription.plistRepresentation)

        let newMaf = try MetaAudioFileDescription(data: data)

        #expect(newMaf == mafDescription)

        #expect(newMaf.tagProperties?.tags.count == 28)
    }
}
