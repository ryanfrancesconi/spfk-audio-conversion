// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata

extension AudioEditRenderer {
    /// Copies the source's metadata onto the render, and refuses the render when any of it could
    /// not be copied.
    ///
    /// A render stands in for the source on Save, so a render without the source's tags would
    /// replace the file with one that has lost them. The render is removed and the source left as
    /// it is.
    func carryMetadata(to resolvedOutput: URL) async throws {
        let converter = AudioFormatConverter(
            source: AudioFormatConverterSource(
                input: sourceURL,
                output: resolvedOutput,
                options: AudioFormatConverterOptions(),
                metadataCopyScheme: metadataCopyScheme
            )
        )

        await converter.copyMetadata()

        let failures = await converter.source.metadataFailures

        guard failures.isEmpty else {
            try? FileManager.default.removeItem(at: resolvedOutput)

            let reasons = failures.map(\.reason).joined(separator: "; ")
            throw NSError(
                description: "The metadata of \(sourceURL.lastPathComponent) could not be carried onto the render: \(reasons)"
            )
        }
    }

    /// Reads the source's markers, moves them onto the trimmed timeline, and re-writes them to
    /// `outputURL`, overwriting the unadjusted markers `copyMetadata` already wrote.
    ///
    /// - Parameter newDuration: duration of the render, bounding a region that ran past the
    ///   out-point.
    ///
    /// - Returns: `false` when the markers could not be written.
    func adjustAndWriteMarkers(to outputURL: URL, newDuration: TimeInterval) async -> Bool {
        guard let outputType = AudioFileType(pathExtension: outputURL.pathExtension) else { return true }

        let collection: AudioMarkerDescriptionCollection
        do {
            collection = try await AudioMarkerDescriptionCollection(url: sourceURL)
        } catch {
            // The source has no markers to move.
            return true
        }

        guard collection.count > 0 else { return true }

        let adjusted = AudioMarkerDescription.adjustedForTrim(
            collection.markerDescriptions,
            inPoint: edit.trim.inPoint,
            outPoint: edit.trim.outPoint,
            newDuration: newDuration
        )

        // An empty set has to clear the file rather than skip it: `copyMetadata` already wrote the
        // source's markers at their pre-trim times, and leaving them is worse than having none.
        guard adjusted.isNotEmpty else {
            AudioFormatConverter.removeMarkers(from: outputURL, outputType: outputType)
            return true
        }

        return AudioFormatConverter.writeMarkers(adjusted, to: outputURL, outputType: outputType)
    }
}
