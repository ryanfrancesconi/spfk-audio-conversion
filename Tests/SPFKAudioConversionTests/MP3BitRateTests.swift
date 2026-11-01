// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// `bitRate` is a stereo rate, so a mono MP3 is written at half of it.
@Suite(.tags(.file))
class MP3BitRateTests: BinTestCase {
    @Test(arguments: [(UInt32(1), 64.0), (2, 128.0)])
    func monoHalvesTheStereoBitRate(channels: UInt32, expectedKbps: Double) async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(channels)ch.mp3", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions(format: .mp3)
        options.bitRate = 128_000
        options.channels = channels

        try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()

        #expect(try AVAudioFile(forReading: output).fileFormat.channelCount == channels)

        let track = try #require(try await AVURLAsset(url: output).loadTracks(withMediaType: .audio).first)
        let kbps = Double(try await track.load(.estimatedDataRate)) / 1000

        #expect(abs(kbps - expectedKbps) < expectedKbps * 0.05, "expected \(expectedKbps) kbps, wrote \(kbps)")
    }
}
