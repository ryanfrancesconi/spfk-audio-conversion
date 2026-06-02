// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase

/// Renders segments from multiple source files to a shared output directory.
///
/// Each item produces one ``SegmentDivider`` run. Files are processed sequentially to avoid
/// overwhelming I/O; within each file, ``SegmentDivider`` processes up to 4 segments concurrently.
///
/// ```swift
/// let items = selectedElements.compactMap { element -> BatchSegmentRenderer.Item? in
///     let segments = element.mafDescription.markerCollection.markerDescriptions
///         .filter { $0.markerType == .region }
///         .compactMap { desc -> TrimDescription? in
///             guard let end = desc.endTime else { return nil }
///             return TrimDescription(inPoint: desc.startTime, outPoint: end)
///         }
///     guard !segments.isEmpty else { return nil }
///     return BatchSegmentRenderer.Item(sourceURL: element.url, segments: segments)
/// }
/// let renderer = BatchSegmentRenderer(items: items, outputDirectory: dir, options: opts)
/// let total = try await renderer.render()
/// ```
public struct BatchSegmentRenderer: Sendable {
    /// A single source file paired with its detected segment boundaries.
    public struct Item: Sendable {
        public let sourceURL: URL
        public let segments: [TrimDescription]

        public init(sourceURL: URL, segments: [TrimDescription]) {
            self.sourceURL = sourceURL
            self.segments = segments
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

    /// Renders all items and returns the total number of output files created.
    /// - Parameter progressHandler: Called after each source file completes, with (completedCount, totalCount).
    @discardableResult
    public func render(
        progressHandler: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws -> Int {
        var total = 0
        for (i, item) in items.enumerated() {
            guard !item.segments.isEmpty else { continue }
            try Task.checkCancellation()
            let divider = SegmentDivider(
                sourceURL: item.sourceURL,
                segments: item.segments,
                outputDirectory: outputDirectory,
                options: options
            )
            let urls = try await divider.divide()
            total += urls.count
            await progressHandler?(i + 1, items.count)
        }
        return total
    }
}
