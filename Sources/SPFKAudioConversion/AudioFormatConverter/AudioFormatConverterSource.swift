// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase

/// Describes the input file, output file, and options for a single conversion operation.
public struct AudioFormatConverterSource: Sendable {
    /// The source audio file URL.
    public var input: URL

    /// The destination URL for the converted file.
    public var output: URL

    /// Options controlling sample rate, bit depth, channels, format, and more.
    public var options: AudioFormatConverterOptions

    /// Copy or ignore source metadata
    public var metadataCopyScheme: MetadataCopyScheme

    /// An `AVURLAsset` created from ``input``. A new instance is returned on each access.
    public var asset: AVURLAsset { AVURLAsset(url: input) }

    /// Changes the converter had to make to ``options`` for the output format to accept them.
    /// Empty when the requested options were used as given.
    ///
    /// The conversion still succeeds; this is what lets a caller tell the user that what they
    /// asked for was not what they got.
    public var adjustments: [AudioFormatConverterAdjustment] = []

    /// Creates a conversion source.
    public init(
        input: URL,
        output: URL,
        options: AudioFormatConverterOptions,
        metadataCopyScheme: MetadataCopyScheme = .copyAll
    ) {
        self.input = input
        self.output = output
        self.options = options
        self.metadataCopyScheme = metadataCopyScheme
    }
}

/// A conversion option the output format could not honor, and what was used instead.
public enum AudioFormatConverterAdjustment: Sendable, Equatable {
    /// The output format does not encode at `requested`, so `applied` was used.
    /// Opus is the case in practice: it accepts only 8/12/16/24/48 kHz.
    case sampleRate(requested: Double, applied: Double, format: AudioFileType)
}
