// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class AssetWriterErrorTests: BinTestCase {
    // MARK: - Nil format throws

    @Test func nilFormatThrows() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = nil

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)

        await #expect(throws: Error.self) {
            try await writer.start()
        }
    }

    // MARK: - Unsupported format throws

    @Test func unsupportedFormatThrows() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac // rejected by setter, stays nil

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)

        await #expect(throws: Error.self) {
            try await writer.start()
        }
    }

    // MARK: - M4A caps sample rate at 48kHz

    @Test func m4aCapsHighSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a
        options.sampleRate = 96000

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        let outputFile = try AVAudioFile(forReading: output)
        // M4A should cap at 48kHz
        #expect(outputFile.fileFormat.sampleRate <= 48000)
    }

    // MARK: - PCM to M4A succeeds

    @Test func pcmToM4ASucceeds() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)
        try await writer.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }
}
