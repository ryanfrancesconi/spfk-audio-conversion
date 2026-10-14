// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AudioToolbox
import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// An AAC output keeps the priming and padding its encoder recorded, so it plays exactly the
/// input's frames whether or not metadata is copied onto it.
@Suite(.tags(.file))
class GaplessConversionTests: BinTestCase {
    private static func validFrames(_ url: URL) throws -> Int64 {
        var id: AudioFileID?
        try #require(AudioFileOpenURL(url as CFURL, .readPermission, 0, &id) == noErr)
        let file = try #require(id)
        defer { AudioFileClose(file) }

        var info = AudioFilePacketTableInfo()
        var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
        try #require(AudioFileGetProperty(file, kAudioFilePropertyPacketTableInfo, &size, &info) == noErr)
        return info.mNumberValidFrames
    }

    @Test(arguments: [MetadataCopyScheme.ignore, .copyAll])
    func anM4AOutputPlaysTheInputLength(scheme: MetadataCopyScheme) async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "gapless-\(scheme.includesText).m4a", directoryHint: .notDirectory)

        try await AudioFormatConverter(source: AudioFormatConverterSource(
            input: input, output: output, options: AudioFormatConverterOptions(format: .m4a), metadataCopyScheme: scheme
        )).start()

        #expect(try Self.validFrames(output) == AVAudioFile(forReading: input).length)
    }
}
