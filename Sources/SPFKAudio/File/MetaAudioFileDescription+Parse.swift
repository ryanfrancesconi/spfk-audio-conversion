// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKLoudness
import SPFKMetadata
import SPFKMetadataC
import SPFKUtils

extension MetaAudioFileDescription {
    public init(parsing url: URL) async throws {
        self.url = url
        urlProperties = URLProperties(url: url)
        fileType = AudioFileType(url: url)
        audioFormat = try AudioFormatProperties(audioFile: AVAudioFile(forReading: url))

        if fileType == .wav {
            try loadWave()

        } else {
            try await load()
        }

        await updateDefaultImage()
    }

    private mutating func loadWave() throws {
        let waveFile = WaveFileC(path: url.path)

        guard waveFile.load() else {
            throw NSError(description: "Failed to load wave file at \(url.path)")
        }

        if let audioProperties = waveFile.audioProperties {
            tagProperties.audioProperties = TagAudioProperties(cObject: audioProperties)
        }

        iXMLMetadata = waveFile.iXML
        bextDescription = waveFile.bext ?? BEXTDescription()

        if let audioMarkers = waveFile.markers as? [AudioMarker] {
            markerCollection = AudioMarkerDescriptionCollection(audioMarkers: audioMarkers)
        }

        // INFO
        if let dict = waveFile.infoDictionary as? [String: String] {
            for item in dict {
                guard let key = InfoFrameKey(value: item.key) else {
                    Log.error("Unhandled INFO frame", item)
                    continue
                }

                tagProperties.data.set(infoFrame: key, value: item.value)
            }
        }

        // ID3
        if let dict = waveFile.id3Dictionary as? [String: String] {
            for item in dict {
                guard let key = ID3FrameKey(value: item.key) else {
                    tagProperties.data.set(taglibKey: item.key, value: item.value)
                    continue
                }

                switch key {
                case .picture:
                    continue
                case .userDefined:
                    Log.error("User Defined", item.value)
                default:
                    tagProperties.data.set(id3Frame: key, value: item.value)
                }
            }
        }

        imageDescription.pictureRef = waveFile.tagPicture?.pictureRef
    }

    private mutating func load() async throws {
        tagProperties = try TagProperties(url: url)

        if let value = try? await AudioMarkerDescriptionCollection(url: url) {
            markerCollection = value
        }

        imageDescription.pictureRef = try? await TagPictureRef.parsing(url: url)
    }

    private mutating func updateDefaultImage() async {
        if imageDescription.cgImage == nil {
            imageDescription.cgImage = url.bestImageRepresentation?.cgImage
            imageDescription.description = url.path
        }

        await imageDescription.createThumbnail()
    }
}
