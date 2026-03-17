// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Numerics
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKUtils
import Testing

import SPFKAudioConverterC

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class ConversionPathTests: BinTestCase {
    // MARK: - convertToWave convenience

    @Test func convertToWaveConvenience() async throws {
        let input = TestBundleResources.shared.tabla_m4a
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }
        
        try await AudioFormatConverter.convertToWave(
            inputURL: input,
            outputURL: output,
            sampleRate: 44100,
            bitDepth: 16
        )

        #expect(output.exists)

        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.fileFormat.sampleRate == 44100)
        let streamDesc = outputFile.fileFormat.streamDescription.pointee
        #expect(streamDesc.mBitsPerChannel == 16)
    }

    // MARK: - AssetWriter paths (PCM output via AVFoundation)

    @Test func assetWriterPCMToAIFF() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function)\(Entropy.uniqueId).aiff", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }
        
        var options = AudioFormatConverterOptions()
        options.format = .aiff

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)
        try await writer.start()

        #expect(output.exists)
        
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func assetWriterPCMToCAF() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).caf", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }
        
        var options = AudioFormatConverterOptions()
        options.format = .caf

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)
        try await writer.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func assetWriterPCMToWAV() async throws {
        let input = TestBundleResources.shared.tabla_aif
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)
        try await writer.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    // MARK: - Compressed to compressed

    @Test func convertM4AToMP3() async throws {
        let input = TestBundleResources.shared.tabla_m4a
        let output = bin.appending(component: "\(#function).mp3", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertMP3ToM4A() async throws {
        let input = TestBundleResources.shared.tabla_mp3
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    // MARK: - FLAC / OGG cross-format

    @Test func convertFLACToMP3() async throws {
        let input = TestBundleResources.shared.tabla_flac
        let output = bin.appending(component: "\(#function).mp3", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertOGGToMP3() async throws {
        let input = TestBundleResources.shared.tabla_ogg
        let output = bin.appending(component: "\(#function).mp3", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertMP3ToFLAC() async throws {
        let input = TestBundleResources.shared.tabla_mp3
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertMP3ToOGG() async throws {
        let input = TestBundleResources.shared.tabla_mp3
        let output = bin.appending(component: "\(#function).ogg", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertM4AToFLAC() async throws {
        let input = TestBundleResources.shared.tabla_m4a
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    @Test func convertM4AToOGG() async throws {
        let input = TestBundleResources.shared.tabla_m4a
        let output = bin.appending(component: "\(#function).ogg", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }

    // MARK: - FLAC with options

    @Test func convertToFLACWithBitDepth16() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac
        options.bitsPerChannel = 16

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        // AVAudioFile reports mBitsPerChannel=0 for FLAC; use libsndfile to verify
        var sampleRate: Int32 = 0, channels: Int32 = 0, bitDepth: Int32 = 0
        let status = SndFileConverter().fileInfo(output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth)
        #expect(status == 0)
        #expect(bitDepth == 16)
    }

    @Test func convertToFLACWithBitDepth24() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac
        options.bitsPerChannel = 24

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        var sampleRate: Int32 = 0, channels: Int32 = 0, bitDepth: Int32 = 0
        let status = SndFileConverter().fileInfo(output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth)
        #expect(status == 0)
        #expect(bitDepth == 24)
    }

    @Test func convertToFLACWithSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac
        options.sampleRate = 22050

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        var sampleRate: Int32 = 0, channels: Int32 = 0, bitDepth: Int32 = 0
        let status = SndFileConverter().fileInfo(output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth)
        #expect(status == 0)
        #expect(sampleRate == 22050)
    }

    @Test func convertToOGGWithSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).ogg", directoryHint: .notDirectory)

        // Opus only supports specific sample rates (8000, 12000, 16000, 24000, 48000).
        // Use 48000 to verify the resample path works with a valid Opus rate.
        var options = AudioFormatConverterOptions()
        options.format = .ogg
        options.sampleRate = 48000

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        var sampleRate: Int32 = 0, channels: Int32 = 0, bitDepth: Int32 = 0
        let status = SndFileConverter().fileInfo(output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth)
        #expect(status == 0)
        #expect(sampleRate == 48000)
    }

    // MARK: - M4A with custom bit rate

    @Test func convertToM4AWithBitRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a
        options.bitRate = 128_000

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration.isApproximatelyEqual(to: 4.39375, relativeTolerance: 0.05))
    }
}
