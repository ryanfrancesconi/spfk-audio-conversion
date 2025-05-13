// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.file))
class AudioFileTypeTests: BinTestCase {
    @Test func checkPathExtension() throws {
        var extensions = AudioFileType.allCases.filter { $0 != .unknown }.map { $0.pathExtension }
        extensions += ["AIF"]

        for aft in extensions {
            let instance = AudioFileType(pathExtension: aft)

            #expect(instance != .unknown)
            #expect(instance.utType != .data)
        }
    }
}
