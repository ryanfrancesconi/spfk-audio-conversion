import AVFoundation
import Numerics
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class AudioFormatConverterTests: BinTestCase {
    func convert(input: URL, output: URL, options: AudioFormatConverterOptions?, expectedDuration: TimeInterval)
        async throws
    {
        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        let outputAVFile = try AVAudioFile(forReading: output)

        // MP3 may round duration
        #expect(
            outputAVFile.duration.isApproximatelyEqual(to: expectedDuration, relativeTolerance: 0.05)
        )

        Log.debug("✓ Wrote \(output.lastPathComponent)")
    }

    // MARK: - Tests

    // CoreAudio
    @Test func convertToPCM() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)
        try await convert(input: input, output: output, options: nil, expectedDuration: 4.39375)
    }

    // convertPCMToCompressed()
    @Test func convertToM4A() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)
        try await convert(input: input, output: output, options: nil, expectedDuration: 4.39375)
    }

    // SoX
    @Test func convertToMP3() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).mp3", directoryHint: .notDirectory)
        try await convert(input: input, output: output, options: nil, expectedDuration: 4.39375)
    }

    // Requires converting input to PCM first
    @Test func convertToMP3NonStandardInput() async throws {
        let input = TestBundleResources.shared.tabla_6_channel
        let output = bin.appending(component: "\(#function).mp3", directoryHint: .notDirectory)
        try await convert(input: input, output: output, options: nil, expectedDuration: 3.86612)
    }

    // convertCompressed()
    @Test func convertToM4AFromMP4() async throws {
        let input = TestBundleResources.shared.tabla_mp4
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)
        try await convert(input: input, output: output, options: nil, expectedDuration: 4.39375)
    }

    @Test func allExportPresetsToMP4() async throws {
        let input = TestBundleResources.shared.tabla_mp4
        let asset = AVURLAsset(url: input)

        for preset in AVAssetExportSession.allExportPresets() {
            let output = bin.appending(component: "\(preset).mp4", directoryHint: .notDirectory)

            guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: .mp4)
            else {
                Log.error("Incompatible preset", preset)
                continue
            }

            let converter = AudioFormatConverter(inputURL: input, outputURL: output)

            let result = try await converter.convert(with: preset)
            #expect(result.exists)
            Log.debug("✓ Wrote \(result.lastPathComponent)")
        }

        #expect(bin.directoryContents?.count == 13)
    }
}
