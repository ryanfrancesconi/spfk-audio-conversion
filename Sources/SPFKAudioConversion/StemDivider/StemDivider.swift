// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata

/// Divides a single audio file into separate files, one per detected segment.
///
/// Provide a source URL and an array of ``TrimDescription`` values (from ``StemSegmentDetector``
/// or read back from "In NN" region markers), then call ``divide()`` to render each segment
/// to its own file. Up to 4 segments render concurrently.
///
/// Output files are named `{stem}_{index:03d}.{ext}` — e.g. `FX_Hits_001.wav`, `FX_Hits_002.wav`.
public actor StemDivider {
    /// The audio file to divide.
    public let sourceURL: URL

    /// Pre-detected segment boundaries. Each entry produces one output file.
    public let segments: [TrimDescription]

    /// Directory where output files are written. Defaults to the same directory as ``sourceURL``.
    public let outputDirectory: URL

    /// Options controlling per-segment processing and output format.
    public var options: StemDividerOptions

    /// - Parameters:
    ///   - sourceURL: The audio file to divide.
    ///   - segments: Detected segments — each becomes one output file.
    ///   - outputDirectory: Where to write output files. Pass `nil` to use the source file's directory.
    ///   - options: Processing and format options.
    public init(
        sourceURL: URL,
        segments: [TrimDescription],
        outputDirectory: URL? = nil,
        options: StemDividerOptions = StemDividerOptions()
    ) {
        self.sourceURL = sourceURL
        self.segments = segments
        self.outputDirectory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        self.options = options
    }

    /// Divides the source into one file per segment and returns the output URLs in segment order.
    ///
    /// Up to 4 segments are rendered concurrently. The returned array is ordered by segment
    /// index and has the same length as ``segments``.
    ///
    /// - Throws: If the source cannot be read or any segment fails to render.
    public func divide() async throws -> [URL] {
        guard !segments.isEmpty else { return [] }

        let gains: [Float]
        if options.normalizeEach {
            gains = try computePeakGains()
        } else {
            gains = [Float](repeating: 1.0, count: segments.count)
        }

        let outputExt = options.outputFormat?.pathExtension ?? sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        var results = [URL?](repeating: nil, count: segments.count)

        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            let maxConcurrent = 4
            var submitted = 0

            func enqueue(_ i: Int) {
                let segment = segments[i]
                let gain = gains[i]
                let dest = makeOutputURL(stem: stem, index: i + 1, extension: outputExt)
                group.addTask { [self] in
                    (i, try await renderSegment(segment: segment, gain: gain, outputURL: dest))
                }
                submitted += 1
            }

            while submitted < min(maxConcurrent, segments.count) {
                enqueue(submitted)
            }

            while let (index, url) = try await group.next() {
                results[index] = url
                if submitted < segments.count {
                    enqueue(submitted)
                }
            }
        }

        return results.compactMap { $0 }
    }

    // MARK: - Private

    private func makeOutputURL(stem: String, index: Int, extension ext: String) -> URL {
        outputDirectory
            .appendingPathComponent("\(stem)_\(String(format: "%03d", index))")
            .appendingPathExtension(ext)
    }

    private func renderSegment(
        segment: TrimDescription,
        gain: Float,
        outputURL: URL
    ) async throws -> URL {
        let normalize = abs(gain - 1.0) >= 0.001
            ? NormalizeDescription(gain: gain)
            : NormalizeDescription()

        let fade = FadeDescription(
            inTime: options.fadeInTime,
            outTime: options.fadeOutTime
        )

        let edit = AudioEditDescription(trim: segment, normalize: normalize, fade: fade)

        let sourceExt = sourceURL.pathExtension.lowercased()
        let needsConversion = options.outputFormat.map { $0.pathExtension != sourceExt } ?? false

        guard needsConversion else {
            let renderer = AudioEditRenderer(
                sourceURL: sourceURL,
                edit: edit,
                outputURL: outputURL,
                fileConflictScheme: options.fileConflictScheme
            )
            return try await renderer.render()
        }

        // Render to an intermediate WAV, then convert to target format.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let renderer = AudioEditRenderer(
            sourceURL: sourceURL,
            edit: edit,
            outputURL: tempURL,
            fileConflictScheme: .overwrite
        )
        try await renderer.render()

        var convOptions = options.conversionOptions ?? AudioFormatConverterOptions()
        convOptions.format = options.outputFormat
        convOptions.conflictScheme = options.fileConflictScheme

        let convSource = AudioFormatConverterSource(
            input: tempURL,
            output: outputURL,
            options: convOptions,
            metadataCopyScheme: .copyAll
        )
        let converter = AudioFormatConverter(source: convSource)
        try await converter.start()
        return convSource.output
    }

    /// Reads the source file once and computes the peak-normalizing gain for each segment.
    /// Gains are capped at 10× (~20 dB) to prevent runaway boost on near-silent segments.
    private func computePeakGains() throws -> [Float] {
        let file = try AVAudioFile(forReading: sourceURL)
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = file.length

        return try segments.map { segment in
            let startFrame = AVAudioFramePosition(segment.inPoint * sampleRate)
            let endFrame: AVAudioFramePosition = segment.outPoint > 0
                ? min(AVAudioFramePosition(segment.outPoint * sampleRate), totalFrames)
                : totalFrames

            let frameCount = max(0, endFrame - startFrame)
            guard frameCount > 0 else { return 1.0 }

            file.framePosition = startFrame

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else { return 1.0 }

            try file.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))

            let peakAmplitude = (try? buffer.peak())?.amplitude ?? 0
            guard peakAmplitude > 0.001 else { return 1.0 }
            return min(1.0 / peakAmplitude, 10.0)
        }
    }
}
