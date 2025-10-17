// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFAudio
import AVFoundation
import SPFKUtils

/// Get audio data from a file suitable for waveform visualization
public class WaveformDataParser {
    public weak var delegate: WaveformDataParserDelegate?

    private var resolution: WaveformDrawingResolution = .medium
    private var priority: TaskPriority = .medium
    private var task: Task<FloatChannelData, Error>?

    public init(
        resolution: WaveformDrawingResolution = .medium,
        priority: TaskPriority = .medium,
        delegate: WaveformDataParserDelegate? = nil
    ) {
        self.resolution = resolution
        self.priority = priority
        self.delegate = delegate
    }

    deinit {
        Log.debug("* { WaveformDataParser }")
    }

    public func parse(url: URL) async throws -> FloatChannelData {
        try await parse(
            audioFile: try AVAudioFile(forReading: url)
        )
    }

    public func parse(audioFile: AVAudioFile) async throws -> FloatChannelData {
        let benchmark = Benchmark(label: "\(#function) \(audioFile.url.path)"); defer { benchmark.stop() }

        // store the current frame before scanning the file
        let currentFrame = audioFile.framePosition

        defer {
            // return the file to frame is was on previously
            audioFile.framePosition = currentFrame
        }

        let task = Task<FloatChannelData, Error>(priority: priority) {
            try await _parse(audioFile: audioFile)
        }

        self.task = task

        switch await task.result {
        case let .success(value):
            return value

        case let .failure(value):
            throw value
        }
    }

    public func cancel() {
        task?.cancel()
    }
}

extension WaveformDataParser {
    private func _parse(audioFile: AVAudioFile) async throws -> FloatChannelData {
        var lastSentProgress: ProgressValue1 = 0
        func send(progress: ProgressValue1) {
            guard let delegate,
                  progress - lastSentProgress >= 0.06 else { return }

            // don't send too many progress events
            lastSentProgress = progress
            delegate.waveformDataParser(event: .loading(string: nil, progress: progress))
        }

        let totalFrames = AVAudioFrameCount(audioFile.length)

        guard totalFrames > 0 else {
            throw NSError(description: "No audio was found in \(audioFile.url.path)")
        }

        let samplesPerPoint: Int = resolution.samplesPerPoint

        // analysis buffer size
        var framesPerBuffer: AVAudioFrameCount = AVAudioFrameCount(samplesPerPoint)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: framesPerBuffer
        ), buffer.frameCapacity > 0 else {
            throw NSError(description: "Unable to create buffer")
        }

        let channelCount = audioFile.fileFormat.channelCount.int
        let outputLength = totalFrames.int / samplesPerPoint
        var floatChannelData = Array(repeating: [Float](zeros: outputLength), count: channelCount)
        var currentFrame: AVAudioFramePosition = 0
        let chunkLength = framesPerBuffer.int

        // scan a chunk and take the max magnitude in it, discard the rest
        for i in 0 ..< outputLength {
            try Task.checkCancellation()

            audioFile.framePosition = currentFrame

            try audioFile.read(into: buffer, frameCount: framesPerBuffer)

            guard let floatData = buffer.floatChannelData else {
                throw NSError(description: "Failed to read from buffer")
            }

            // let length = vDSP_Length(buffer.frameLength).int

            for n in 0 ..< channelCount {
                var value: Float = .nan

                let bufferPointer = UnsafeBufferPointer(start: floatData[n], count: chunkLength)
                let floatArray = Array(bufferPointer)

                for item in floatArray {
                    value = Float.maximumMagnitude(item, value)
                }

                if !value.isNaN {
                    floatChannelData[n][i] = value
                }
            }

            currentFrame += AVAudioFramePosition(framesPerBuffer)

            // buffer has reached end of file, trim it
            if currentFrame + AVAudioFramePosition(framesPerBuffer) > totalFrames {
                framesPerBuffer = totalFrames - AVAudioFrameCount(currentFrame)

                guard framesPerBuffer > 0 else { break }
            }

            send(progress: currentFrame.double / totalFrames.double)
        }

        delegate?.waveformDataParser(event: .loaded)

        return floatChannelData
    }
}

public protocol WaveformDataParserDelegate: AnyObject {
    func waveformDataParser(event: LoadStateEvent)
}
