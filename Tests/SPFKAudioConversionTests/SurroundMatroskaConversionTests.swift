// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// Converting a 5.1 Matroska file goes through an intermediate file, and the downmix follows that
/// file's layout, so a center fold-in is only right when the decoder's labels survive the trip.
@Suite(.tags(.file))
class SurroundMatroskaConversionTests: BinTestCase {
    static let fixtures = [
        TestBundleResources.shared.surround_eac3_mka,
        TestBundleResources.shared.surround_aac_mka,
        TestBundleResources.shared.surround_opus_mka,
    ]

    @Test(arguments: fixtures, [AudioFileType.mp3, .wav])
    func stereoKeepsTheCenter(url: URL, format: AudioFileType) async throws {
        let name = url.deletingPathExtension().lastPathComponent
        let output = bin.appending(component: "\(name).\(format.pathExtension)", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions(format: format)
        options.channels = 2

        try await AudioFormatConverter(inputURL: url, outputURL: output, options: options).start()

        let (samples, sampleRate) = try MultichannelConversionTests.channels(of: output)
        try #require(samples.count == 2)

        let tones = TestBundleResources.surroundTones
        let center = tones[2]

        for channel in 0 ..< 2 {
            let level = MultichannelConversionTests.toneLevel(samples[channel], hz: center, sampleRate: sampleRate)
            #expect(level > 0.03, "\(name) → \(format): center on channel \(channel) at \(level)")
        }

        // Left stays left: its tone dominates the left output and not the right.
        let leftOnLeft = MultichannelConversionTests.toneLevel(samples[0], hz: tones[0], sampleRate: sampleRate)
        let leftOnRight = MultichannelConversionTests.toneLevel(samples[1], hz: tones[0], sampleRate: sampleRate)
        #expect(leftOnLeft > leftOnRight * 4, "\(name) → \(format): left \(leftOnLeft) / \(leftOnRight)")
    }

    @Test(arguments: fixtures)
    func flacKeepsEveryChannel(url: URL) async throws {
        let output = bin.appending(component: url.deletingPathExtension().lastPathComponent + ".flac", directoryHint: .notDirectory)

        try await AudioFormatConverter(
            inputURL: url,
            outputURL: output,
            options: AudioFormatConverterOptions(format: .flac)
        ).start()

        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.channelCount == 6)
    }
}
