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

@Suite(.tags(.file))
class ConversionPathTests: BinTestCase {
    // MARK: - Compressed input to WAV

    @Test func compressedInputConvertsToWave() async throws {
        let input = TestBundleResources.shared.tabla_m4a
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .wav
        options.sampleRate = 44100
        options.bitsPerChannel = 16

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

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

    // MARK: - Ogg codec identity

    /// The codec carried in an Ogg container, read from the identification header of the
    /// first page. `.ogg` and `.opus` differ only here — both are Ogg, and every other
    /// property a converted file exposes is identical.
    private enum OggCodec {
        case vorbis, opus, unknown

        init(contentsOf url: URL) throws {
            let head = try Data(contentsOf: url).prefix(1024)

            // Vorbis identification header: packet type 0x01 followed by "vorbis".
            let vorbisMagic = Data([0x01]) + Data("vorbis".utf8)
            let opusMagic = Data("OpusHead".utf8)

            if head.range(of: vorbisMagic) != nil {
                self = .vorbis
            } else if head.range(of: opusMagic) != nil {
                self = .opus
            } else {
                self = .unknown
            }
        }
    }

    @Test func oggOutputIsVorbis() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).ogg", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .ogg

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        #expect(try OggCodec(contentsOf: output) == .vorbis)
    }

    @Test func opusOutputIsOpus() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).opus", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .opus

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)
        #expect(try OggCodec(contentsOf: output) == .opus)
    }

    /// Opus encodes only at 8/12/16/24/48 kHz, so a requested rate outside that set is
    /// snapped to the nearest supported one rather than failing the write.
    @Test func opusSnapsUnsupportedSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).opus", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .opus
        options.sampleRate = 44100

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        var sampleRate: Int32 = 0, channels: Int32 = 0, bitDepth: Int32 = 0
        let status = SndFileConverter().fileInfo(
            output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth
        )
        #expect(status == 0)
        #expect(sampleRate == 48000)
    }

    /// The snap is silent to the audio but must not be silent to the caller — the UI reports it.
    @Test func opusRecordsSampleRateAdjustment() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).opus", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .opus
        options.sampleRate = 44100

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        let adjustments = await converter.source.adjustments

        #expect(
            adjustments == [
                .sampleRate(requested: 44100, applied: 48000, format: .opus)
            ]
        )
    }

    /// A rate the output format accepts is used as given, and reported as no adjustment.
    @Test func opusAtSupportedRateRecordsNoAdjustment() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).opus", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .opus
        options.sampleRate = 48000

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        let adjustments = await converter.source.adjustments
        #expect(adjustments.isEmpty)
    }

    /// Vorbis has no rate restriction, so a rate Opus would reject is preserved.
    @Test func vorbisPreservesUnsupportedOpusSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).ogg", directoryHint: .notDirectory)
        if output.exists { try? output.delete() }

        var options = AudioFormatConverterOptions()
        options.format = .ogg
        options.sampleRate = 44100

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        var sampleRate: Int32 = 0, channels: Int32 = 0, bitDepth: Int32 = 0
        let status = SndFileConverter().fileInfo(
            output.path, sampleRate: &sampleRate, channels: &channels, bitDepth: &bitDepth
        )
        #expect(status == 0)
        #expect(sampleRate == 44100)
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
