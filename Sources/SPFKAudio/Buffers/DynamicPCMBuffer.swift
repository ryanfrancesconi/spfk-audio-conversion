// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFoundation
import OTAtomics
import SwiftExtensions

public class DynamicPCMBuffer {
    private(set) var internalBuffer: AVAudioPCMBuffer

    public var channelCount: Int {
        Int(internalBuffer.format.channelCount)
    }

    public var frameLength: AVAudioFrameCount {
        internalBuffer.frameLength
    }

    public var format: AVAudioFormat {
        internalBuffer.format
    }

    public lazy var rms: Float = {
        internalBuffer.rmsValue
    }()

    public lazy var peak: Peak? = {
        try? internalBuffer.peak()
    }()

    @OTAtomicsThreadSafe public internal(set) var _abortFlag: Bool = false
    @OTAtomicsThreadSafe public internal(set) var _isProcessing: Bool = false

    // MARK: - Init

    /// Read the contents of the url into this buffer
    public convenience init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        try self.init(file: file)
    }

    /// Read entire file and return a new AVAudioPCMBuffer with its contents
    public convenience init(file: AVAudioFile) throws {
        file.framePosition = 0

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw NSError(description: "Failed to create buffer from file")
        }

        try file.read(into: buffer)

        self.init(buffer: buffer)
    }

    public init(buffer: AVAudioPCMBuffer) {
        internalBuffer = buffer
    }
}
