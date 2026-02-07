import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKAudioC
import SPFKBase

public actor BpmAnalysis: Sendable {
    private var task: Task<Bpm, Error>?

    public func process(url: URL) async throws -> Bpm {
        try await process(audioFile: AVAudioFile(forReading: url))
    }

    public func process(audioFile: AVAudioFile) async throws -> Bpm {
        let benchmark = Benchmark(label: "\((#file as NSString).lastPathComponent):\(#function)"); defer { benchmark.stop() }

        // store the current frame before scanning the file
        let currentFrame = audioFile.framePosition

        defer {
            // return the file to frame is was on previously
            audioFile.framePosition = currentFrame
        }

        let task = Task<Bpm, Error>(priority: .high) {
            try await _process(audioFile: audioFile)
        }

        self.task = task

        let result = await task.result

        guard !task.isCancelled else {
            throw CancellationError()
        }

        switch result {
        case let .success(value):
            return value

        case let .failure(error):
            Log.error("Failed parsing \(audioFile.url)", error)
            throw error
        }
    }

    public func cancel() {
        guard let task else {
            Log.error("task is nil")
            return
        }

        task.cancel()
    }

    private func _process(audioFile: AVAudioFile) async throws -> Bpm {
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let sampleRate = audioFile.fileFormat.sampleRate

        guard totalFrames > 0 else {
            throw NSError(description: "No audio was found in \(audioFile.url.path)")
        }

        Log.debug(audioFile.url.lastPathComponent, audioFile.duration, "seconds")

        // analysis buffer size
        var framesPerBuffer = AVAudioFrameCount(8 * sampleRate) // x seconds

        if framesPerBuffer > totalFrames {
            framesPerBuffer = totalFrames
        }

        let pcmFormat = audioFile.processingFormat

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: framesPerBuffer
        )
        else {
            throw NSError(description: "Unable to create buffer")
        }

        var currentFrame: AVAudioFramePosition = 0

        var bpms: [Bpm] = []

        while currentFrame < totalFrames {
            audioFile.framePosition = currentFrame

            try audioFile.read(into: buffer, frameCount: framesPerBuffer)

            do {
                let average = try evaluateBpm(buffer: buffer)

                if bpms.count(of: average) >= 3 {
                    Log.debug("Returning early found \(bpms) enough multiples of", average)
                    return average
                }

                bpms.append(average)

            } catch {
                Log.error(error)
            }

            currentFrame += AVAudioFramePosition(framesPerBuffer)

            // buffer has reached end of file, trim it
            if currentFrame + AVAudioFramePosition(framesPerBuffer) > totalFrames {
                framesPerBuffer = totalFrames - AVAudioFrameCount(currentFrame)

                guard framesPerBuffer > 0 else { break }
            }
        }

        return try chooseMostLikelyBpm(from: bpms)
    }

    func chooseMostLikelyBpm(from bpms: [Bpm]) throws -> Bpm {
        guard bpms.isNotEmpty else {
            throw NSError(description: "failed to detect bpm")
        }

        let frequencyMap = bpms.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }

        let multiples = frequencyMap.filter { $1 > 1 }.keys

        guard let value = multiples.first else {
            return bpms[0] // unideal, but pick first
        }

        Log.debug("elements which have more than one entry:", multiples)

        return value
    }

    func evaluateBpm(buffer: AVAudioPCMBuffer) throws -> Bpm {
//        let monoBuffer = try buffer.convertToMono()
//        guard monoBuffer.format.channelCount == 1, let rawData = monoBuffer.floatChannelData else {
//            throw NSError(description: "Failed to read from buffer")
//        }

        guard let rawData = buffer.floatChannelData else {
            throw NSError(description: "Failed to get data from buffer")
        }

        let channelCount = buffer.format.channelCount.int
        let sampleRate = buffer.format.sampleRate
        let framesPerBuffer = buffer.frameLength

        var channelBpms = [Double](repeating: Double.nan, count: channelCount)

        for n in 0 ..< channelCount {
            channelBpms[n] = BpmEstimation.processMbpm(rawData[n], numberOfSamples: Int32(framesPerBuffer), sampleRate: sampleRate)
        }

        let average: Double = channelBpms.averaged.rounded(.down)

        // let average: Double = BpmEstimation.processMbpm(rawData[0], numberOfSamples: Int32(framesPerBuffer), sampleRate: sampleRate)
        // Log.debug("average", average)

        return try Bpm(average)
    }
}

extension [Double] {
    public var averaged: Double {
        reduce(0, +) / Double(count)
    }
}

extension AVAudioPCMBuffer {
    func convertToMono() throws -> AVAudioPCMBuffer {
        let buffer = self

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(description: "failed to create mono format")
        }

        guard let monoBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: buffer.frameCapacity
        ) else {
            throw NSError(description: "failed to create mono buffer")
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: monoFormat) else {
            throw NSError(description: "failed to create converter")
        }

        try converter.convert(to: monoBuffer, from: buffer)

        monoBuffer.frameLength = buffer.frameLength

        return monoBuffer
    }
}
