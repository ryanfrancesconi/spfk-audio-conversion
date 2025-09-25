// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

public struct MetaAudioFileDescription: Hashable, Codable {
    public var url: URL?

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
        self.url = url
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

        self.url = url

        fileType = AudioFileType(url: url)

        tagProperties = try TagProperties(url: url)

        if fileType == .wav {
            bextDescription = BEXTDescription(url: url)
        }
    }
}
