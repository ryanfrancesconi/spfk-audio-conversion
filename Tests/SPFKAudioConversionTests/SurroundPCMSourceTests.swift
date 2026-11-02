// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AudioToolbox
import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// Every PCM source opens a 5.1 file and delivers each tone on the channel its layout names.
///
/// Asserted by label rather than by index: each codec decodes in its own order, and the layout is
/// what tells loudness and downmix which channel is which.
@Suite(.tags(.file))
struct SurroundPCMSourceTests {
    static let toneByLabel: [AudioChannelLabel: Double] = {
        let tones = TestBundleResources.surroundTones

        return [
            kAudioChannelLabel_Left: tones[0],
            kAudioChannelLabel_Right: tones[1],
            kAudioChannelLabel_Center: tones[2],
            kAudioChannelLabel_LFEScreen: tones[3],
            kAudioChannelLabel_LeftSurround: tones[4],
            kAudioChannelLabel_RearSurroundLeft: tones[4],
            kAudioChannelLabel_RightSurround: tones[5],
            kAudioChannelLabel_RearSurroundRight: tones[5],
        ]
    }()

    static func labels(of format: AVAudioFormat) throws -> [AudioChannelLabel] {
        let layout = try #require(format.channelLayout)
        var tag = layout.layoutTag
        var size: UInt32 = 0

        try #require(AudioFormatGetPropertyInfo(kAudioFormatProperty_ChannelLayoutForTag, 4, &tag, &size) == noErr)

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { raw.deallocate() }

        try #require(AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutForTag, 4, &tag, &size, raw) == noErr)

        let expanded = raw.assumingMemoryBound(to: AudioChannelLayout.self)
        let count = Int(expanded.pointee.mNumberChannelDescriptions)
        let offset = try #require(MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions))
        let first = UnsafeRawPointer(expanded).advanced(by: offset).assumingMemoryBound(to: AudioChannelDescription.self)

        return UnsafeBufferPointer(start: first, count: count).map(\.mChannelLabel)
    }

    /// Reads one second from a quarter second in, past any priming.
    static func read(_ source: some SeekablePCMSource) throws -> AVAudioPCMBuffer {
        let rate = source.processingFormat.sampleRate
        try source.seek(toFrame: AVAudioFramePosition(rate / 4))

        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(rate)))
        let destination = try #require(buffer.floatChannelData)
        var filled: AVAudioFrameCount = 0

        while filled < buffer.frameCapacity {
            let chunk = try #require(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: buffer.frameCapacity - filled))
            let read = try source.readNextChunk(into: chunk, frameCount: chunk.frameCapacity)

            guard read > 0 else { break }

            let source = try #require(chunk.floatChannelData)

            for channel in 0 ..< Int(chunk.format.channelCount) {
                (destination[channel] + Int(filled)).update(from: source[channel], count: Int(read))
            }

            filled += read
        }

        buffer.frameLength = filled
        return buffer
    }

    static func expectTonesByLabel(_ source: some SeekablePCMSource) throws {
        let format = source.processingFormat
        try #require(format.channelCount == 6)

        let labels = try labels(of: format)
        let buffer = try read(source)
        let data = try #require(buffer.floatChannelData)
        try #require(buffer.frameLength > 0)

        for (channel, label) in labels.enumerated() {
            let hz = try #require(toneByLabel[label], "label \(label)")
            let samples = Array(UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
            let level = MultichannelConversionTests.toneLevel(samples, hz: hz, sampleRate: format.sampleRate)

            #expect(level > 0.1, "channel \(channel), label \(label): \(level) at \(hz) Hz")
        }
    }

    // MARK: - Matroska

    static let matroskaFixtures = [
        TestBundleResources.shared.surround_eac3_mka,
        TestBundleResources.shared.surround_ac3_mka,
        TestBundleResources.shared.surround_aac_mka,
        TestBundleResources.shared.surround_flac_mka,
        TestBundleResources.shared.surround_opus_mka,
    ]

    @Test(arguments: matroskaFixtures)
    func matroskaDecoderDeliversEveryChannel(url: URL) throws {
        try Self.expectTonesByLabel(MatroskaAudioDecoder(url: url))
    }

    @Test func stereoMatroskaKeepsTheStandardFormat() throws {
        let decoder = try MatroskaAudioDecoder(url: TestBundleResources.shared.stereo_eac3_mka)

        #expect(decoder.processingFormat == AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
    }

    // MARK: - libsndfile

    @Test(arguments: [TestBundleResources.shared.surround_vorbis_ogg, TestBundleResources.shared.surround_opus_opus])
    func sndFileSourceDeliversEveryChannel(url: URL) throws {
        try Self.expectTonesByLabel(SndFilePCMSource(url: url))
    }

    // MARK: - AVAssetReader

    /// Lossless, so the reader's samples are held to `AVAudioFile`'s exactly, channel by channel.
    @Test func assetReaderMatchesTheFileReadOnEveryChannel() async throws {
        let url = TestBundleResources.shared.tabla_6_channel
        let source = try await AVAssetReaderPCMSource(url: url)

        #expect(source.processingFormat.channelCount == 6)
        #expect(source.processingFormat.channelLayout?.channelCount == 6)

        let buffer = try Self.read(source)
        let data = try #require(buffer.floatChannelData)

        let file = try AVAudioFile(forReading: url)
        file.framePosition = AVAudioFramePosition(file.processingFormat.sampleRate / 4)
        let reference = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: buffer.frameLength))
        try file.read(into: reference, frameCount: buffer.frameLength)
        let expected = try #require(reference.floatChannelData)

        try #require(reference.frameLength == buffer.frameLength)

        for channel in 0 ..< 6 {
            let mismatch = (0 ..< Int(buffer.frameLength)).first { data[channel][$0] != expected[channel][$0] }
            #expect(mismatch == nil, "channel \(channel) differs at frame \(mismatch ?? -1)")
        }
    }

    // MARK: - Format

    @Test(arguments: [1, 2])
    func monoAndStereoAreTheStandardFormats(channels: Int) throws {
        let format = try #require(AVAudioFormat.pcmProcessingFormat(sampleRate: 48000, channelCount: AVAudioChannelCount(channels), layoutTag: nil))

        #expect(format == AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels)))
    }

    @Test func moreThanTwoChannelsWithoutALayoutAreDiscrete() throws {
        let format = try #require(AVAudioFormat.pcmProcessingFormat(sampleRate: 48000, channelCount: 4, layoutTag: nil))

        #expect(format.channelCount == 4)
        #expect(format.channelLayout?.layoutTag == kAudioChannelLayoutTag_DiscreteInOrder | 4)
    }
}
