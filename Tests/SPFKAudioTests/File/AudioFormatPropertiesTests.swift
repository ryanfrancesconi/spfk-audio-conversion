import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKBase
import Testing

@Suite(.tags(.file))
struct AudioFormatPropertiesTests {
    @Test func bitrate() async throws {
        for url in TestBundleResources.shared.formats {
            let audioFile = try AVAudioFile(forReading: url)

            let properties = AudioFormatProperties(audioFile: audioFile)
            
            Log.debug(url.lastPathComponent, properties.formatDescription)
            
        }
    }
}
