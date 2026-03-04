// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation

public struct AudioFormatConverterSource: Sendable {
    /// The source audio file
    public var input: URL

    /// The audio file to be created after conversion
    public var output: URL

    /// Options for conversion
    public var options: AudioFormatConverterOptions

    public var asset: AVURLAsset { AVURLAsset(url: input) }

    public init(input: URL, output: URL, options: AudioFormatConverterOptions) {
        self.input = input
        self.output = output
        self.options = options
    }
}
