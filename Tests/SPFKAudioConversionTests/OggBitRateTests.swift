// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// The bit rate the options ask for reaches the Vorbis and Opus encoders.
@Suite(.tags(.file))
class OggBitRateTests: BinTestCase {
    /// Average kbps of `url`, from its size and the source's duration.
    private func kbps(_ url: URL, seconds: Double) throws -> Double {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return Double(bytes) * 8 / seconds / 1000
    }

    @Test(arguments: [
        (AudioFileType.ogg, UInt32(128_000)), (.ogg, 256_000),
        (.opus, 64000), (.opus, 192_000),
    ])
    func theRequestedBitRateIsApproximatelyWhatIsWritten(format: AudioFileType, bitRate: UInt32) async throws {
        let input = TestBundleResources.shared.tabla_wav
        let source = try AVAudioFile(forReading: input)
        let seconds = Double(source.length) / source.fileFormat.sampleRate
        #expect(source.fileFormat.channelCount == 2)

        let output = bin.appending(component: "\(bitRate).\(format.pathExtension)", directoryHint: .notDirectory)
        var options = AudioFormatConverterOptions(format: format)
        options.bitRate = bitRate

        try await AudioFormatConverter(inputURL: input, outputURL: output, options: options).start()

        let written = try kbps(output, seconds: seconds)
        let requested = Double(bitRate) / 1000

        // Both encoders are variable rate, so this asks for the neighborhood, not the number.
        #expect(abs(written - requested) < requested * 0.3, "asked \(requested) kbps, wrote \(written)")
    }
}
