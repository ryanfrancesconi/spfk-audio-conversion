// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase
import SPFKMetadata

/// Renders segments from multiple source files to a shared output directory.
///
/// Each item produces one ``SegmentDivider`` run. Files are processed sequentially to avoid
/// overwhelming I/O; within each file, ``SegmentDivider`` processes up to 4 segments concurrently.
///
/// ```swift
/// let items = selectedElements.compactMap { element -> BatchSegmentRenderer.Item? in
///     let allMarkers = element.mafDescription.markerCollection.markerDescriptions
///     let segments = allMarkers
///         .filter { $0.markerType == .region }
///         .compactMap { desc -> TrimDescription? in
///             guard let end = desc.endTime else { return nil }
///             return TrimDescription(inPoint: desc.startTime, outPoint: end)
///         }
///     guard !segments.isEmpty else { return nil }
///     return BatchSegmentRenderer.Item(sourceURL: element.url, segments: segments, markers: allMarkers)
/// }
/// let renderer = BatchSegmentRenderer(items: items, outputDirectory: dir, options: opts)
/// let total = try await renderer.render()
/// ```
public struct BatchSegmentRenderer: Sendable {
    /// A single source file paired with its detected segment boundaries.
    ///
    /// Pass all source markers in ``markers``; ``SegmentDivider`` will write only the cue markers
    /// (those without an `endTime`) that fall within each segment's time window.
    public struct Item: Sendable {
        public let sourceURL: URL
        public let segments: [TrimDescription]
        /// All markers from the source file. Cue markers are routed to the matching output segment.
        public let markers: [AudioMarkerDescription]

        public init(sourceURL: URL, segments: [TrimDescription], markers: [AudioMarkerDescription] = []) {
            self.sourceURL = sourceURL
            self.segments = segments
            self.markers = markers
        }
    }

    public let items: [Item]
    public let outputDirectory: URL
    public let options: SegmentDividerOptions

    public init(
        items: [Item],
        outputDirectory: URL,
        options: SegmentDividerOptions = SegmentDividerOptions()
    ) {
        self.items = items
        self.outputDirectory = outputDirectory
        self.options = options
    }

    /// Renders all items and returns the output file URLs.
    /// - Parameter progressHandler: Called after each source file completes, with (completedCount, totalCount).
    @discardableResult
    public func render(
        progressHandler: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> [URL] {
        var outputURLs: [URL] = []
        for (i, item) in items.enumerated() {
            guard !item.segments.isEmpty else { continue }
            try Task.checkCancellation()
            let divider = SegmentDivider(
                sourceURL: item.sourceURL,
                segments: item.segments,
                outputDirectory: outputDirectory,
                options: options,
                markers: item.markers
            )
            let urls = try await divider.divide()
            outputURLs.append(contentsOf: urls)
            await progressHandler?(i + 1, items.count)
        }
        return outputURLs
    }
}
