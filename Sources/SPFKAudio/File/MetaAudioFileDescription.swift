// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AppKit
import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

public struct MetaAudioFileDescription: Hashable, Codable {
    public var urlProperties: URLProperties?

    public var url: URL? { urlProperties?.url }

    public var fileType: AudioFileType?

    public var audioFormat: AudioFormatProperties?

    public var tagProperties: TagProperties?

    /// BEXT Wave Chunk - BroadcastExtension - only applicable for wave files
    public var bextDescription: BEXTDescription?

    /// LUFS, true peak and loudness range
    public var loudness: LoudnessDescription?

    public init(
        url: URL? = nil,
        fileType: AudioFileType? = nil,
        audioFormat: AudioFormatProperties? = nil,
        tagProperties: TagProperties? = nil,
        bextDescription: BEXTDescription? = nil,
        loudness: LoudnessDescription? = nil
    ) {
        if let url {
            urlProperties = URLProperties(url: url)
        }

        self.fileType = fileType
        self.audioFormat = audioFormat
        self.tagProperties = tagProperties
        self.bextDescription = bextDescription
        self.loudness = loudness
    }
}

extension MetaAudioFileDescription {
    public init(parsing url: URL) throws {
        let avAudioFile = try AVAudioFile(forReading: url)

        audioFormat = AudioFormatProperties(avAudioFile: avAudioFile)

        urlProperties = URLProperties(url: url)

        fileType = AudioFileType(url: url)

        tagProperties = try TagProperties(url: url)

        if fileType == .wav {
            bextDescription = BEXTDescription(url: url)
        }
    }
}

public struct URLProperties: Hashable, Codable {
    public var url: URL
    public var finderTags: FinderTagGroup

    public init(url: URL) {
        self.url = url
        self.finderTags = FinderTagGroup(url: url)
    }
}
