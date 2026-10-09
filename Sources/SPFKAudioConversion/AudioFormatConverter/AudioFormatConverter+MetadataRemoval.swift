// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata

extension AudioFormatConverter {
    /// Removes from a verbatim copy what ``AudioFormatConverterSource/metadataCopyScheme`` leaves
    /// out, since the copy brought everything across. Failures are recorded in
    /// ``AudioFormatConverterSource/metadataFailures``.
    func removeExcludedMetadata() {
        let scheme = source.metadataCopyScheme
        let output = source.output

        guard scheme != .copyAll else { return }

        if !scheme.includesFinderTags, output.tagNames.isNotEmpty {
            do {
                try output.removeAllTags()
            } catch {
                recordMetadataFailure(.finderTags, error)
            }
        }

        guard let outputType = AudioFileType(pathExtension: output.pathExtension),
              AudioFileType.metadataTypes.contains(outputType)
        else { return }

        if !scheme.includesText {
            removeText(outputType: outputType)
        }

        if !scheme.includesMarkers {
            AudioFormatConverter.removeMarkers(from: output, outputType: outputType)
        }

        if !scheme.includesImage, (try? EmbeddedArtwork.read(from: output)) != nil {
            do {
                try EmbeddedArtwork.remove(from: output)
            } catch {
                recordMetadataFailure(.artwork, "The image could not be removed")
            }
        }
    }

    /// Strips tags, BEXT and iXML, keeping an image the scheme asks for: in a WAV it lives in the
    /// ID3 chunk the strip removes.
    private func removeText(outputType: AudioFileType) {
        let output = source.output
        let keptImage = source.metadataCopyScheme.includesImage ? try? EmbeddedArtwork.read(from: output) : nil

        if outputType == .wav {
            do {
                try ProductionChunks.removeAll(from: output, fileType: .wav)
            } catch {
                recordMetadataFailure(.bext, "BEXT and iXML could not be removed")
                recordMetadataFailure(.ixml, "BEXT and iXML could not be removed")
            }
        }

        do {
            try TagProperties.removeAllTags(in: output)
        } catch {
            recordMetadataFailure(.tags, error)
        }

        if let keptImage {
            do {
                try keptImage.write(to: output)
            } catch {
                recordMetadataFailure(.artwork, "The image could not be kept")
            }
        }
    }
}
