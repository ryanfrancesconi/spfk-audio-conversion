// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Numerics
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class PCMConversionTests: BinTestCase {
    // MARK: - Sample rate conversion

    @Test func convertSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.sampleRate = 22050

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.fileFormat.sampleRate == 22050)
    }

    // MARK: - Bit depth conversion

    @Test func convertBitDepth24To16() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.bitsPerChannel = 16

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        let streamDesc = outputFile.fileFormat.streamDescription.pointee
        #expect(streamDesc.mBitsPerChannel == 16)
    }

    // MARK: - Channel conversion

    @Test func convertStereoToMono() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.channels = 1

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.fileFormat.channelCount == 1)
    }

    // MARK: - Same-format copy path

    @Test func sameFormatCopiesFile() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        // Parse options from input so they match exactly
        let options = AudioFormatConverterOptions(url: input)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        // File should be identical (copied, not re-encoded)
        let inputData = try Data(contentsOf: input)
        let outputData = try Data(contentsOf: output)
        #expect(inputData == outputData)
    }

    // MARK: - WAV to CAF

    @Test func convertWavToCAF() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).caf", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .caf

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration.isApproximatelyEqual(to: 4.39375, relativeTolerance: 0.05))
    }

    // MARK: - AIFF to WAV

    @Test func convertAIFFToWav() async throws {
        let input = TestBundleResources.shared.tabla_aif
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    // MARK: - Compressed input to PCM output

    @Test func convertM4AToWav() async throws {
        let input = TestBundleResources.shared.tabla_m4a
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.bitsPerChannel = 16

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertMP3ToWav() async throws {
        let input = TestBundleResources.shared.tabla_mp3
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.bitsPerChannel = 16

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    // MARK: - Combined options

    @Test func convertWithMultipleOptions() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.sampleRate = 22050
        options.bitsPerChannel = 16
        options.channels = 1

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.fileFormat.sampleRate == 22050)
        #expect(outputFile.fileFormat.channelCount == 1)
        let streamDesc = outputFile.fileFormat.streamDescription.pointee
        #expect(streamDesc.mBitsPerChannel == 16)
    }
}
