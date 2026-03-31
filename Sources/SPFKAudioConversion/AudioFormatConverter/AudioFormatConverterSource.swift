// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

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

    public var outputExists: Bool { output.exists }
    
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
