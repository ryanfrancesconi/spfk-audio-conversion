import AVFoundation
@testable import SPFKAudio
import SPFKMetadata
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized)
class SoXTests: BinTestCase {
    @Test func convertMP3() throws {
        let input = BundleResources.shared.tabla_wav
        let output = bin.appendingPathComponent("test.mp3")

        SoX().convertMP3(input: input.path, output: output.path, bitRate: 256, sampleRate: 48000)

        let avFile = try AVAudioFile(forReading: output)
        #expect(avFile.duration == 4.44)
        #expect(MetaAudioFileFormat.detectFileType(url: output) == .mp3)
    }

    @Test func convertAIFF() throws {
        let input = BundleResources.shared.tabla_wav
        let output = bin.appendingPathComponent("test.aiff")

        SoX().convert(input: input.path, output: output.path, bitDepth: 24, sampleRate: 48000)

        let avFile = try AVAudioFile(forReading: output)
        #expect(avFile.duration == 4.39375)
        #expect(avFile.fileFormat.sampleRate == 48000)
        #expect(MetaAudioFileFormat.detectFileType(url: output) == .aiff)
    }

    @Test func createMultiChannelWave() throws {
        deleteBinOnExit = false

        let input = BundleResources.shared.tabla_wav

        let url1 = bin.appendingPathComponent("wave1.wav")
        try? url1.delete()

        try FileManager.default.copyItem(at: input, to: url1)

        let url2 = bin.appendingPathComponent("wave2.wav")
        try? url2.delete()

        try FileManager.default.copyItem(at: input, to: url2)

        let url3 = bin.appendingPathComponent("wave3.wav")
        try? url3.delete()

        try FileManager.default.copyItem(at: input, to: url3)

        let output = bin.appendingPathComponent("\(input.deletingPathExtension().lastPathComponent) 3 channels.wav")
        #expect(
            SoX().createMultiChannelWave(
                input: [url1, url2, url3],
                output: output
            )
        )

        let avFile = try AVAudioFile(forReading: output)
        #expect(avFile.duration == 4.39375)
        #expect(avFile.fileFormat.sampleRate == 48000)
        #expect(MetaAudioFileFormat.detectFileType(url: output) == .wav)
    }

    @Test func exportStereoChannels() throws {
        let input = BundleResources.shared.tabla_wav
        let channelPair = try SoX().exportSplitStereo(input: input, destination: bin, overwrite: true)

        #expect(channelPair.left.exists)
        #expect(channelPair.right.exists)
    }

    @Test func exportInvalidStereoChannels() throws {
        let input = BundleResources.shared.no_data_chunk
        let bin = self.bin

        #expect(throws: (any Error).self) {
            _ = try SoX().exportSplitStereo(input: input, destination: bin, overwrite: true)
        }
    }

    @Test func testExportMultipleChannels() throws {
        let input = BundleResources.shared.tabla_6_channel

        let urls = try SoX().exportChannels(input: input, destination: bin, newName: "TEST")
        let directoryContents = try #require(bin.directoryContents).filter { $0.lastPathComponent.contains("TEST") } // read actual files in bin

        #expect(urls.count == 6)
        #expect(directoryContents.count == 6)

        let expected = ["TEST.1.wav", "TEST.2.wav", "TEST.3.wav", "TEST.4.wav", "TEST.5.wav", "TEST.6.wav"]

        #expect(
            directoryContents.map { $0.lastPathComponent } == expected
        )
    }

    @Test func trim() throws {
        let input = BundleResources.shared.tabla_wav
        let output = bin.appendingPathComponent("trimmed.wav")

        #expect(
            SoX().trim(input: input, output: output, startTime: 1, endTime: 2)
        )

        let avFile = try AVAudioFile(forReading: output)
        #expect(avFile.duration == 1)
    }

    @Test func stereoToMono() throws {
        let input = BundleResources.shared.tabla_wav

        let result = try #require(
            SoX().stereoToMono(source: input, destination: bin)
        )

        let avFile = try AVAudioFile(forReading: result)

        #expect(avFile.fileFormat.channelCount == 1)
    }
}
