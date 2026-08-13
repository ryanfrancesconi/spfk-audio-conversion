// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AudioToolbox
import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// WAV output is written as `kAudioFileRF64Type` so a conversion past 4 GiB has somewhere to go.
/// Core Audio only writes RF64 magic once the data actually crosses that boundary; below it the
/// file is a plain `RIFF`/`WAVE` carrying a 28-byte `JUNK` placeholder where `ds64` would sit.
/// These tests pin the small-file half — that the placeholder changes nothing observable — because
/// the crossing itself needs a 4.5 GB fixture and is proved by hand.
@Suite(.tags(.file))
class LongPCMOutputTests: BinTestCase {
    private func convert(
        _ input: URL,
        to output: URL,
        format: AudioFileType,
        sampleRate: Double? = nil,
        bitsPerChannel: UInt32? = nil
    ) async throws {
        var options = AudioFormatConverterOptions()
        options.format = format
        options.sampleRate = sampleRate
        options.bitsPerChannel = bitsPerChannel

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()
    }

    /// Reads the four-character chunk name at `offset`.
    private func fourCC(_ url: URL, at offset: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: 4) ?? Data()
        return String(data: data, encoding: .ascii) ?? ""
    }

    private func fileTypeID(of url: URL) -> AudioFileTypeID? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
            return nil
        }
        defer { AudioFileClose(file) }

        var type: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &size, &type) == noErr else {
            return nil
        }
        return type
    }

    private func dataFormat(of url: URL) -> AudioStreamBasicDescription? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
            return nil
        }
        defer { AudioFileClose(file) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &asbd) == noErr else {
            return nil
        }
        return asbd
    }

    // MARK: - Small output is unchanged in kind

    /// A short conversion still reports as WAVE to every reader, and carries the placeholder that
    /// only becomes `ds64` past 4 GiB.
    ///
    /// The depth change is load-bearing, and has to differ from the source: `cowbell.wav` is
    /// 24-bit, and with the output matching the input in every respect `convertToPCM` copies the
    /// file instead of writing one, so the writer type is never exercised.
    @Test func shortWavOutputIsStillPlainWave() async throws {
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)
        try await convert(
            TestBundleResources.shared.cowbell_wav,
            to: output,
            format: .wav,
            bitsPerChannel: 16
        )

        #expect(try fourCC(output, at: 0) == "RIFF")
        #expect(try fourCC(output, at: 8) == "WAVE")
        #expect(try fourCC(output, at: 12) == "JUNK")
        #expect(fileTypeID(of: output) == kAudioFileWAVEType)
    }

    /// The placeholder sits where a chunk walker would look first, so anything reading the output
    /// has to skip it. AVFoundation is the one every product goes through.
    @Test func shortWavOutputDecodes() async throws {
        let input = TestBundleResources.shared.cowbell_wav
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)
        try await convert(input, to: output, format: .wav, bitsPerChannel: 16)

        let source = try AVAudioFile(forReading: input)
        let result = try AVAudioFile(forReading: output)

        #expect(result.fileFormat.sampleRate == source.fileFormat.sampleRate)
        #expect(result.fileFormat.channelCount == source.fileFormat.channelCount)
        #expect(result.length == source.length)
    }

    /// 8-bit WAV samples are unsigned, and that flag is keyed on the container the samples are laid
    /// out for — so the writer type has to be chosen separately from the format passed here.
    /// Handing `createOutputDescription` the RF64 id instead would leave 8-bit output signed.
    ///
    /// Reachable from an 8-bit input with no explicit depth: `bitsPerChannel` clamps to 16...32,
    /// so the option cannot ask for it directly.
    @Test func eightBitWavDescriptionStaysUnsigned() throws {
        var input = AudioStreamBasicDescription()
        input.mSampleRate = 44100
        input.mChannelsPerFrame = 2
        input.mBitsPerChannel = 8

        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = nil

        let asWave = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileWAVEType,
            inputDescription: input
        )

        #expect(asWave.mBitsPerChannel == 8)
        #expect(asWave.mFormatFlags & kAudioFormatFlagIsSignedInteger == 0)

        // What passing the writer type through here would have produced.
        let asRF64 = AudioFormatConverter.createOutputDescription(
            options: options,
            outputFormatID: kAudioFileRF64Type,
            inputDescription: input
        )

        #expect(asRF64.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0)
    }

    /// AIFF has no long form to promote to, so it keeps a hard limit and must not acquire the
    /// placeholder.
    @Test func aiffOutputIsUnaffected() async throws {
        let output = bin.appending(component: "\(#function).aif", directoryHint: .notDirectory)
        try await convert(TestBundleResources.shared.cowbell_wav, to: output, format: .aiff)

        #expect(try fourCC(output, at: 0) == "FORM")
        #expect(try fourCC(output, at: 8) == "AIFF")
        #expect(fileTypeID(of: output) == kAudioFileAIFFType)
    }

    // MARK: - The AIFF ceiling is keyed on output size

    /// The old limit read the *input* file's size, which is wrong in both directions: it missed a
    /// small file that grows under a rate or depth increase, and refused a large one that shrinks.
    @Test func estimatedOutputSizeScalesWithSampleRate() throws {
        let input = TestBundleResources.shared.cowbell_wav

        var file: ExtAudioFileRef?
        try #require(ExtAudioFileOpenURL(input as CFURL, &file) == noErr)
        let strongFile = try #require(file)
        defer { ExtAudioFileDispose(strongFile) }

        var inputDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try #require(
            ExtAudioFileGetProperty(
                strongFile, kExtAudioFileProperty_FileDataFormat, &size, &inputDescription
            ) == noErr
        )

        func estimate(sampleRate: Double, bitsPerChannel: UInt32) -> UInt64 {
            var options = AudioFormatConverterOptions()
            options.sampleRate = sampleRate
            options.bitsPerChannel = bitsPerChannel

            let outputDescription = AudioFormatConverter.createOutputDescription(
                options: options,
                outputFormatID: kAudioFileAIFFType,
                inputDescription: inputDescription
            )

            return AudioFormatConverter.estimatedOutputBytes(
                file: strongFile,
                inputDescription: inputDescription,
                outputDescription: outputDescription
            )
        }

        let base = estimate(sampleRate: inputDescription.mSampleRate, bitsPerChannel: 16)
        #expect(base > 0)

        // Doubling the rate doubles the bytes; so does going 16-bit to 32-bit.
        let doubleRate = estimate(sampleRate: inputDescription.mSampleRate * 2, bitsPerChannel: 16)
        #expect(doubleRate == base * 2)

        let doubleDepth = estimate(sampleRate: inputDescription.mSampleRate, bitsPerChannel: 32)
        #expect(doubleDepth == base * 2)
    }

    /// An unreadable length leaves the limit unenforced rather than failing the conversion on a
    /// number that could not be established.
    @Test func estimatedOutputSizeIsZeroWhenTheRateIsUnknown() throws {
        let input = TestBundleResources.shared.cowbell_wav

        var file: ExtAudioFileRef?
        try #require(ExtAudioFileOpenURL(input as CFURL, &file) == noErr)
        let strongFile = try #require(file)
        defer { ExtAudioFileDispose(strongFile) }

        // A zeroed description: sample rate 0, which is what an unreadable input looks like.
        let empty = AudioStreamBasicDescription()
        let outputDescription = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: 0,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
        )

        #expect(
            AudioFormatConverter.estimatedOutputBytes(
                file: strongFile,
                inputDescription: empty,
                outputDescription: outputDescription
            ) == 0
        )
    }
}
