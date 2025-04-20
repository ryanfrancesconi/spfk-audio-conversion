// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFoundation
import OTAtomics
import OTCore

public class DynamicPCMBuffer {
    private(set) var internalBuffer: AVAudioPCMBuffer {
        didSet {
            _rms = nil
        }
    }

    public var channelCount: Int {
        Int(internalBuffer.format.channelCount)
    }

    public var frameLength: AVAudioFrameCount {
        internalBuffer.frameLength
    }

    public var format: AVAudioFormat {
        internalBuffer.format
    }

    private var _rms: Float?
    public var rms: Float {
        if let cachedValue = _rms { return cachedValue }
        let value = internalBuffer.rmsValue
        _rms = value
        return value
    }

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
