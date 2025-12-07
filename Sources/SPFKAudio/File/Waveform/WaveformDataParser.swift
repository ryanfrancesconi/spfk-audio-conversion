// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Accelerate
import AVFAudio
import AVFoundation
import SPFKBase

/// Get audio data from a file suitable for waveform visualization
public actor WaveformDataParser {
    public let resolution: WaveformDrawingResolution
    private let priority: TaskPriority

    public weak var delegate: WaveformDataParserDelegate?
    public func update(delegate: WaveformDataParserDelegate?) {
        self.delegate = delegate
    }

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

    public func parse(url: URL) async throws -> WaveformData {
        try await parse(audioFile: AVAudioFile(forReading: url))
    }

    public func parse(audioFile: AVAudioFile) async throws -> WaveformData {
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

        let result = await task.result

        guard !task.isCancelled else {
            throw CancellationError()
        }

        var floatChannelData: FloatChannelData

        switch result {
        case let .success(value):
            floatChannelData = value

        case let .failure(error):
            Log.error("Failed parsing \(audioFile.url)", error)
            throw error
        }

        let waveformData = WaveformData(
            floatChannelData: floatChannelData,
            samplesPerPoint: resolution.samplesPerPoint,
            audioDuration: audioFile.duration,
            sampleRate: audioFile.fileFormat.sampleRate
        )

        await delegate?.waveformDataParser(event:
            .loaded(url: audioFile.url, waveformData: waveformData)
        )

        return waveformData
    }

    public func cancel() {
        guard let task else {
            Log.error("task is nil")
            return
        }

        task.cancel()
    }
}

extension WaveformDataParser {
    private func _parse(audioFile: AVAudioFile) async throws -> FloatChannelData {
        guard resolution != .lossless else {
            return try await readEntire(audioFile: audioFile)
        }

        let url = audioFile.url

        var lastSentProgress: UnitInterval = 0
        func send(progress: UnitInterval) async {
            await delegate?.waveformDataParser(event: .loading(url: url, progress: progress))
        }

        let totalFrames = AVAudioFrameCount(audioFile.length)
        let totalFramesDouble = Double(totalFrames)

        guard totalFrames > 0 else {
            throw NSError(description: "No audio was found in \(audioFile.url.path)")
        }

        // will be >= 1
        let samplesPerPoint: Int = resolution.samplesPerPoint

        // analysis buffer size
        var framesPerBuffer = AVAudioFrameCount(samplesPerPoint)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: framesPerBuffer
        ) else {
            throw NSError(description: "Unable to create buffer")
        }

        let chunkCount = totalFrames.int / samplesPerPoint
        let channelCount = audioFile.fileFormat.channelCount.int
        var currentFrame: AVAudioFramePosition = 0

        // allocates with all 0 values
        var outfloatChannelData = allocateFloatChannelData(length: chunkCount, channelCount: channelCount)

        var chunksSkipped: Set<Int> = .init()

        // scan a chunk and take the max magnitude in it, discard the rest
        for i in 0 ..< chunkCount {
            try Task.checkCancellation()

            audioFile.framePosition = currentFrame

            do {
                try audioFile.read(into: buffer, frameCount: framesPerBuffer)

            } catch {
                chunksSkipped.insert(i)
                continue
            }

            guard let rawData = buffer.floatChannelData else {
                throw NSError(description: "Failed to read from buffer")
            }

            let frameCount = framesPerBuffer.int

            for n in 0 ..< channelCount {
                let bufferPointer = UnsafeBufferPointer(start: rawData[n], count: frameCount)

                let min: Float = vDSP.minimum(bufferPointer)
                let max: Float = vDSP.maximum(bufferPointer)
                let value = Float.maximumMagnitude(min, max)

                // let value = vDSP.rootMeanSquare(bufferPointer)

                if !value.isNaN {
                    outfloatChannelData[n][i] = value
                }
            }

            currentFrame += AVAudioFramePosition(framesPerBuffer)

            // buffer has reached end of file, trim it
            if currentFrame + AVAudioFramePosition(framesPerBuffer) > totalFrames {
                framesPerBuffer = totalFrames - AVAudioFrameCount(currentFrame)

                guard framesPerBuffer > 0 else { break }
            }

            let progress: UnitInterval = Double(currentFrame) / totalFramesDouble

            if progress - lastSentProgress > 0.05 {
                await send(progress: progress)
                lastSentProgress = progress
            }
        }

        if chunksSkipped.isNotEmpty {
            Log.error("audioFile.read error skipped \(chunksSkipped.count)/\(chunkCount) chunks for \(url.path)")
        }

        return outfloatChannelData
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
