// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFAudio
import AVFoundation
import SPFKUtils

/// Get audio data from a file suitable for waveform visualization
public class WaveformDataParser {
    public weak var delegate: WaveformDataParserDelegate?

    public var resolution: WaveformDrawingResolution = .medium
    private var priority: TaskPriority = .medium
    private var task: Task<FloatChannelData, Error>?

    public init(
        resolution: WaveformDrawingResolution,
        priority: TaskPriority = .medium,
        delegate: WaveformDataParserDelegate? = nil
    ) {
        self.resolution = resolution
        self.priority = priority
        self.delegate = delegate
    }

    deinit {
        // Log.debug("* { WaveformDataParser }")
    }

    public func parse(url: URL) async throws -> WaveformData {
        try await parse(
            audioFile: try AVAudioFile(forReading: url)
        )
    }

    public func parse(audioFile: AVAudioFile) async throws -> WaveformData {
        // let benchmark = Benchmark(label: "\(#function) \(audioFile.url.path)"); defer { benchmark.stop() }

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

        var floatChannelData: FloatChannelData

        switch await task.result {
        case let .success(value):
            floatChannelData = value

        case let .failure(error):
            throw error
        }

        let waveformData = WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: resolution.samplesPerPoint,
            audioDuration: audioFile.duration,
            sampleRate: audioFile.fileFormat.sampleRate
        )

        delegate?.waveformDataParser(
            event: .loaded(url: audioFile.url, waveformData: waveformData)
        )

        return waveformData
    }

    public func cancel() {
        task?.cancel()
    }
}

extension WaveformDataParser {
    private func _parse(audioFile: AVAudioFile) async throws -> FloatChannelData {
        guard resolution != .lossless else {
            return try await readEntire(audioFile: audioFile)
        }

        let url = audioFile.url

        var lastSentProgress: ProgressValue1 = 0
        func send(progress: ProgressValue1) {
            guard let delegate,
                  progress - lastSentProgress >= 0.06 else { return }

            // don't send too many progress events
            lastSentProgress = progress
            delegate.waveformDataParser(event: .loading(url: url, progress: progress))
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

        let chunkCount = totalFrames.int / samplesPerPoint
        let channelCount = audioFile.fileFormat.channelCount.int
        var currentFrame: AVAudioFramePosition = 0

        var floatChannelData = newFloatChannelData(channelCount: channelCount, length: chunkCount)

        // scan a chunk and take the max magnitude in it, discard the rest
        for i in 0 ..< chunkCount {
            try Task.checkCancellation()

            audioFile.framePosition = currentFrame

            try audioFile.read(into: buffer, frameCount: framesPerBuffer)

            guard let rawData = buffer.floatChannelData else {
                throw NSError(description: "Failed to read from buffer")
            }

            for n in 0 ..< channelCount {
                var value: Float = .nan

                let bufferPointer = UnsafeBufferPointer(start: rawData[n], count: framesPerBuffer.int)
                let floatArray = Array<Float>(bufferPointer)

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

        return floatChannelData
    }

    /// read the entire file into memory. should only be used on short files
    private func readEntire(audioFile: AVAudioFile) async throws -> FloatChannelData {
        Log.debug("reading entire file \(audioFile.url.path)")

        guard let buffer = try AVAudioPCMBuffer(audioFile: audioFile) else {
            throw NSError(description: "Unable to create buffer")
        }

        guard let floatData = buffer.floatData else {
            throw NSError(description: "Failed to read from buffer")
        }

        return floatData
    }
}

public enum WaveformDataLoadEvent {
    case loading(url: URL, progress: ProgressValue1)
    case loaded(url: URL, waveformData: WaveformData)
}

public protocol WaveformDataParserDelegate: AnyObject {
    func waveformDataParser(event: WaveformDataLoadEvent)
}
