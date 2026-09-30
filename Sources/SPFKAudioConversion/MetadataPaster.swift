// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKMetadataC

/// Reads and writes the BEXT and iXML chunks of WAV and FLAC files, which a conversion carries
/// across separately from the tags TagLib copies.
enum MetadataPaster {}

// MARK: - BEXT

extension MetadataPaster {
    static func readBEXT(from url: URL, type: AudioFileType?) -> BEXTDescription? {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load(), let info = file.bextDescriptionC else { return nil }
            return BEXTDescription(info: info)

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else { return nil }
            return file.bextDescription

        default:
            return nil
        }
    }

    static func writeBEXT(_ bext: BEXTDescription, to url: URL, type: AudioFileType?) throws {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for BEXT writing")
            }
            file.bextDescriptionC = bext.bextDescriptionC
            file.markersNeedsSave = false
            file.imageNeedsSave = false
            guard file.save() else {
                throw NSError(description: "Failed to write BEXT to \(url.lastPathComponent)")
            }

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for BEXT writing")
            }
            file.bextDescription = bext
            guard file.save() else {
                throw NSError(description: "Failed to write BEXT to \(url.lastPathComponent)")
            }

        default:
            break
        }
    }
}

// MARK: - iXML

extension MetadataPaster {
    static func readIXML(from url: URL, type: AudioFileType?) -> String? {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load() else { return nil }
            return file.iXML

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else { return nil }
            return file.iXML

        default:
            return nil
        }
    }

    static func writeIXML(_ xml: String, to url: URL, type: AudioFileType?) throws {
        switch type {
        case .wav:
            let file = WaveFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for iXML writing")
            }
            file.iXML = xml
            file.markersNeedsSave = false
            file.imageNeedsSave = false
            guard file.save() else {
                throw NSError(description: "Failed to write iXML to \(url.lastPathComponent)")
            }

        case .flac:
            let file = FlacFileC(path: url.path)
            guard file.load() else {
                throw NSError(description: "Failed to open \(url.lastPathComponent) for iXML writing")
            }
            file.iXML = xml
            guard file.save() else {
                throw NSError(description: "Failed to write iXML to \(url.lastPathComponent)")
            }

        default:
            break
        }
    }
}
