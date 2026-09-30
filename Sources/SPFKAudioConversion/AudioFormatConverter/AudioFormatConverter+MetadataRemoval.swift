// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKFileSystem
import SPFKMetadata
import SPFKMetadataC

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

        if !scheme.includesImage, (try? TagPictureRef.parsing(url: output)) != nil {
            if !TagPicture.write(nil, path: output.path) {
                recordMetadataFailure(.image, "The image could not be removed")
            }
        }
    }

    /// Strips tags, BEXT and iXML, keeping an image the scheme asks for: in a WAV it lives in the
    /// ID3 chunk the strip removes.
    private func removeText(outputType: AudioFileType) {
        let output = source.output
        let keptImage = source.metadataCopyScheme.includesImage ? try? TagPictureRef.parsing(url: output) : nil

        if outputType == .wav {
            let file = WaveFileC(path: output.path)

            if file.load(), file.bextDescriptionC != nil || file.iXML != nil {
                file.bextDescriptionC = nil
                file.iXML = nil
                file.markersNeedsSave = false
                file.imageNeedsSave = false

                if !file.save() {
                    recordMetadataFailure(.bext, "BEXT and iXML could not be removed")
                }
            }
        }

        do {
            try TagProperties.removeAllTags(in: output)
        } catch {
            recordMetadataFailure(.tags, error)
        }

        if let keptImage, !TagPicture.write(keptImage, path: output.path) {
            recordMetadataFailure(.image, "The image could not be kept")
        }
    }
}
