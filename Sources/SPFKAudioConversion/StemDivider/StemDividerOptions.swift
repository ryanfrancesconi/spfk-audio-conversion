// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase

/// Options controlling per-segment processing and output format for ``StemDivider``.
public struct StemDividerOptions: Sendable {
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
    public var fadeInTime: TimeInterval = 0

    /// Fade-out applied to each segment's end. 0 = none.
    public var fadeOutTime: TimeInterval = 0

    /// Conflict scheme for output files that already exist. Defaults to `.unique`.
    public var fileConflictScheme: FileConflictScheme = .unique

    public init(
        outputFormat: AudioFileType? = nil,
        conversionOptions: AudioFormatConverterOptions? = nil,
        normalizeEach: Bool = false,
        fadeInTime: TimeInterval = 0,
        fadeOutTime: TimeInterval = 0,
        fileConflictScheme: FileConflictScheme = .unique
    ) {
        self.outputFormat = outputFormat
        self.conversionOptions = conversionOptions
        self.normalizeEach = normalizeEach
        self.fadeInTime = fadeInTime
        self.fadeOutTime = fadeOutTime
        self.fileConflictScheme = fileConflictScheme
    }
}
