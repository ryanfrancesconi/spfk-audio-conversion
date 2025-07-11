// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKMetadata

import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

public struct MetaAudioFileDescription: Hashable, Codable {
    public var url: URL?

    public var fileType: AudioFileType?

    public var audioFormat: AudioFormatProperties?

    public var tagProperties: TagProperties?

    public var bextDescription: BEXTDescription?

    /// LUFS, true peak and loudness range
    public var loudness: LoudnessDescription?

    public init(parsing url: URL) throws {
        self.url = url

        fileType = AudioFileType(url: url)

        tagProperties = try TagProperties(url: url)

        if fileType == .wav {
            bextDescription = BEXTDescription(url: url)
        }
    }
}
