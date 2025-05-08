import AVFoundation
@testable import SPFKAudio
import SPFKMetadata
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
class SoXTests: BinTestCase {
    @Test func convertMP3() throws {
        let input = BundleResources.shared.tabla_wav
        let output = bin.appendingPathComponent("test.mp3")

        SoX.shared.convertMP3(input: input, output: output, bitRate: 256, sampleRate: 48000)

        let avFile = try AVAudioFile(forReading: output)
        #expect(avFile.duration == 4.44)
        #expect(MetaAudioFileFormat.detectFileType(url: output) == .mp3)
    }

    @Test func convertPCM() throws {
        let input = BundleResources.shared.tabla_wav

        let formats: [MetaAudioFileFormat] = [.wav, .aiff]

        for format in formats {
            let output = bin.appendingPathComponent("test.\(format.pathExtension)")

            SoX.shared.convertPCM(input: input, output: output, bitDepth: 24, sampleRate: 48000)

            let avFile = try AVAudioFile(forReading: output)

            #expect(avFile.duration.isApproximatelyEqual(to: 4.4, relativeTolerance: 0.1))
            #expect(avFile.fileFormat.sampleRate == 48000)
            #expect(MetaAudioFileFormat.detectFileType(url: output) == format)
        }
    }

    @Test func createMultiChannelWave() throws {
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
            SoX.shared.createMultiChannelWave(
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
        let channelPair = try SoX.shared.exportSplitStereo(input: input, destination: bin, overwrite: true)

        #expect(channelPair.left.exists)
        #expect(channelPair.right.exists)
    }

    @Test func exportInvalidStereoChannels() throws {
        let input = BundleResources.shared.no_data_chunk
        let bin = self.bin

        #expect(throws: (any Error).self) {
            _ = try SoX.shared.exportSplitStereo(input: input, destination: bin, overwrite: true)
        }
    }

    @Test func testExportMultipleChannels() throws {
        let input = BundleResources.shared.tabla_6_channel

        let urls = try SoX.shared.exportChannels(input: input, destination: bin, newName: "TEST")
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
        let output = bin.appendingPathComponent("trimmed\(Entropy.uniqueId).wav")

        #expect(
            SoX.shared.trim(input: input, output: output, startTime: 1, endTime: 2)
        )

        let avFile = try AVAudioFile(forReading: output)
        #expect(avFile.duration == 1)
    }

    @Test func stereoToMono() throws {
        let input = BundleResources.shared.tabla_wav

        let result = try #require(
            SoX.shared.stereoToMono(source: input, destination: bin)
        )

        let avFile = try AVAudioFile(forReading: result)

        #expect(avFile.fileFormat.channelCount == 1)
    }

    @Test func concurrentInstances() async throws {
        let task1 = Task {
            try trim()
        }

        let task2 = Task {
            try trim()
        }

        let task3 = Task {
            //try convertPCM()
            try trim()
        }

        let task4 = Task {
            //try convertMP3()
            try trim()
        }

        try await task1.value
        try await task2.value
        try await task3.value
        try await task4.value
    }
}
