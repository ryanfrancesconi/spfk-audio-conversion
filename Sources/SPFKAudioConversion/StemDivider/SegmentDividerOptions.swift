// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase

/// Options controlling per-segment processing and output format for ``SegmentDivider``.
public struct SegmentDividerOptions: Sendable, Codable {
    /// Output format. `nil` = same extension as source file.
    /// When non-nil and the extension differs from the source, each rendered segment
    /// is converted through ``AudioFormatConverter`` after the initial render.
    public var outputFormat: AudioFileType? = nil

    /// Full conversion options applied when ``outputFormat`` differs from the source.
    /// Ignored when ``outputFormat`` is `nil` or matches the source extension.
    /// If `nil`, converter defaults are used with only the format set.
    public var conversionOptions: AudioFormatConverterOptions? = nil

    /// If `true`, normalize each segment to 0 dBFS peak before writing.
    public var normalizeEach: Bool = false

    /// Fade-in applied to each segment's start. 0 = none.
    public var fadeInTime: TimeInterval = 0.005

    /// Fade-out applied to each segment's end. 0 = none.
    public var fadeOutTime: TimeInterval = 0.005

    /// Conflict scheme for output files that already exist. Defaults to `.unique`.
    public var fileConflictScheme: FileConflictScheme = .unique

    public init(
        outputFormat: AudioFileType? = nil,
        conversionOptions: AudioFormatConverterOptions? = nil,
        normalizeEach: Bool = false,
        fadeInTime: TimeInterval = 0.005,
        fadeOutTime: TimeInterval = 0.005,
        fileConflictScheme: FileConflictScheme = .unique
    ) {
        self.outputFormat = outputFormat
        self.conversionOptions = conversionOptions
        self.normalizeEach = normalizeEach
        self.fadeInTime = fadeInTime
        self.fadeOutTime = fadeOutTime
        self.fileConflictScheme = fileConflictScheme
    }

    // Forward-compatible decode: fields added in future versions fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outputFormat = try c.decodeIfPresent(AudioFileType.self, forKey: .outputFormat) ?? nil
        conversionOptions = try c.decodeIfPresent(AudioFormatConverterOptions.self, forKey: .conversionOptions) ?? nil
        normalizeEach = try c.decodeIfPresent(Bool.self, forKey: .normalizeEach) ?? false
        fadeInTime = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeInTime) ?? 0.005
        fadeOutTime = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeOutTime) ?? 0.005
        fileConflictScheme = try c.decodeIfPresent(FileConflictScheme.self, forKey: .fileConflictScheme) ?? .unique
    }
}
