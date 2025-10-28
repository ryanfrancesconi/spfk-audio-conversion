// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AppKit
import AVFoundation
import Foundation
import SPFKMetadata
import SPFKUtils

public struct MetaAudioFileDescription: Hashable, Codable {
    public var urlProperties: URLProperties

    public var fileType: AudioFileType?

    public var audioFormat: AudioFormatProperties?

    public var tagProperties: TagProperties?

    /// BEXT Wave Chunk - BroadcastExtension - only applicable for wave files
    public var bextDescription: BEXTDescription?

    /// LUFS, true peak and loudness range
    public var loudness: LoudnessDescription?

    // MARK: -

    public var url: URL { urlProperties.url }

    public var tempo: Double? {
        tagProperties?.tags[.bpm]?.double
    }

    // TODO: markers

    public init(
        urlProperties: URLProperties,
        fileType: AudioFileType? = nil,
        audioFormat: AudioFormatProperties? = nil,
        tagProperties: TagProperties? = nil,
        bextDescription: BEXTDescription? = nil,
        loudness: LoudnessDescription? = nil
    ) {
        self.urlProperties = urlProperties
        self.fileType = fileType
        self.audioFormat = audioFormat
        self.tagProperties = tagProperties
        self.bextDescription = bextDescription
        self.loudness = loudness
    }
}

extension MetaAudioFileDescription {
    public init(parsing url: URL) throws {
        audioFormat = AudioFormatProperties(audioFile: try AVAudioFile(forReading: url))

        urlProperties = URLProperties(url: url)

        fileType = AudioFileType(url: url)

        tagProperties = try TagProperties(url: url)

        if fileType == .wav {
            bextDescription = BEXTDescription(url: url)
        }

        // parsing LoudnessDescription requires audio analysis. opt in on a command
    }
}
