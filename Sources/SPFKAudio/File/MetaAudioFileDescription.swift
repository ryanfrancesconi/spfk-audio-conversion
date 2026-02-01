// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import CoreImage
import Foundation
import SPFKAudioBase
import SPFKLoudness
import SPFKMetadata
import SPFKUtils

public struct MetaAudioFileDescription: Hashable, Sendable {
    public var url: URL
    public var urlProperties: URLProperties
    public var fileType: AudioFileType?
    public var audioFormat: AudioFormatProperties?
    public var tagProperties: TagProperties = .init()

    /// Broadcast Extension Wave Chunk - only applicable for wave files
    public var bextDescription: BEXTDescription?

    /// iXML Wave Chunk - only applicable for wave files
    public var iXMLMetadata: String?

    /// Adobe XMP xml
    public var xmpMetadata: String?

    public var markerCollection: AudioMarkerDescriptionCollection = .init()

    public var imageDescription: ImageDescription = .init()

    // MARK: - Properties

    public var bestAvailableImage: CGImage? {
        imageDescription.cgImage ??
            url.bestImageRepresentation?.cgImage
    }

    public var audioProperties: TagAudioProperties? {
        tagProperties.audioProperties
    }

    public var tempo: Double? {
        tagProperties.tags[.bpm]?.double
    }

    /// Convenience suitable for a UI display
    public var loudnessDescription: LoudnessDescription {
        LoudnessDescription(
            loudnessValue: tagProperties.tags[.loudnessIntegrated]?.double,
            loudnessRange: tagProperties.tags[.loudnessRange]?.double,
            maxTruePeakLevel: tagProperties.tags[.loudnessTruePeak]?.float,
            maxMomentaryLoudness: tagProperties.tags[.loudnessMaxMomentary]?.double,
            maxShortTermLoudness: tagProperties.tags[.loudnessMaxShortTerm]?.double,
        )
    }

    public init(
        url: URL,
        urlProperties: URLProperties? = nil,
        fileType: AudioFileType? = nil,
        audioFormat: AudioFormatProperties? = nil,
        tagProperties: TagProperties? = nil,
        bextDescription: BEXTDescription? = nil,
        xmpMetadata: String? = nil,
        iXMLMetadata: String? = nil,
        markerCollection: AudioMarkerDescriptionCollection = .init()
    ) {
        self.url = url
        self.urlProperties = urlProperties ?? URLProperties(url: url)
        self.fileType = fileType
        self.audioFormat = audioFormat

        if let tagProperties {
            self.tagProperties = tagProperties
        }

        self.tagProperties.url = url

        self.bextDescription = bextDescription
        self.xmpMetadata = xmpMetadata
        self.iXMLMetadata = iXMLMetadata
        self.markerCollection = markerCollection
    }
}

extension MetaAudioFileDescription: Codable {
    enum CodingKeys: String, CodingKey {
        case url
        case urlProperties
        case fileType
        case audioFormat
        case tagProperties
        case bextDescription
        case xmpMetadata
        case iXMLMetadata
        case markerCollection
        case imageDescription
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        url = try container.decode(URL.self, forKey: .url)
        urlProperties = try container.decode(URLProperties.self, forKey: .urlProperties)
        tagProperties = try container.decode(TagProperties.self, forKey: .tagProperties)
        imageDescription = try container.decode(ImageDescription.self, forKey: .imageDescription)

        fileType = try? container.decodeIfPresent(AudioFileType.self, forKey: .fileType)
        audioFormat = try? container.decodeIfPresent(AudioFormatProperties.self, forKey: .audioFormat)

        bextDescription = try? container.decodeIfPresent(BEXTDescription.self, forKey: .bextDescription)
        xmpMetadata = try? container.decodeIfPresent(String.self, forKey: .xmpMetadata)
        iXMLMetadata = try? container.decodeIfPresent(String.self, forKey: .iXMLMetadata)

        if let markerCollection = try? container.decodeIfPresent(AudioMarkerDescriptionCollection.self, forKey: .markerCollection) {
            self.markerCollection = markerCollection
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // required
        try container.encode(url, forKey: .url)
        try container.encode(urlProperties, forKey: .urlProperties)
        try container.encode(tagProperties, forKey: .tagProperties)
        try container.encode(imageDescription, forKey: .imageDescription)

        // optionals
        try? container.encodeIfPresent(fileType, forKey: .fileType)
        try? container.encodeIfPresent(audioFormat, forKey: .audioFormat)
        try? container.encodeIfPresent(bextDescription, forKey: .bextDescription)
        try? container.encodeIfPresent(xmpMetadata, forKey: .xmpMetadata)
        try? container.encodeIfPresent(iXMLMetadata, forKey: .iXMLMetadata)

        try? container.encode(markerCollection, forKey: .markerCollection)
    }
}
