import AVFoundation
import SPFKData
import SPFKMetadataXMP
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.file))
class MetaAudioFileDescriptionTests: BinTestCase {
    @Test func codable() async throws {
        let url = TestBundleResources.shared.mp3_id3
        let mafDescription = try await PlaylistElement(parsing: url).mafDescription

        #expect(mafDescription.tagProperties?.tags.count == 28)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        let data = try encoder.encode(mafDescription)

        Log.debug(data.toString())
    }
}
