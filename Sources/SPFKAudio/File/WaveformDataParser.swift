// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFAudio
import AVFoundation
import SPFKUtils

/// Get audio data from a file suitable for waveform visualization
public struct WaveformDataParser {
    public typealias ProgressHandler = ((ProgressValue1) -> Void)?

    private var resolution: WaveformDrawingResolution = .medium
    private var priority: TaskPriority = .medium

    public init(
        resolution: WaveformDrawingResolution = .medium,
        priority: TaskPriority = .medium

    ) {
        self.resolution = resolution
        self.priority = priority
    }

    public func parse(url: URL, progressHandler: ProgressHandler? = nil) async throws -> FloatChannelData {
        try await parse(
            audioFile: try AVAudioFile(forReading: url),
            progressHandler: progressHandler
        )
    }

    public func parse(audioFile: AVAudioFile, progressHandler: ProgressHandler? = nil) async throws -> FloatChannelData {
        let benchmark = Benchmark(label: "\(#function) \(audioFile.url.path)"); defer { benchmark.stop() }

        // store the current frame before scanning the file
        let currentFrame = audioFile.framePosition

        defer {
            // return the file to frame is was on previously
            audioFile.framePosition = currentFrame
        }

        let task = Task<FloatChannelData, Error>(priority: priority) {
            let totalFrames = AVAudioFrameCount(audioFile.length)

            guard totalFrames > 0 else {
                throw NSError(description: "No audio was found in \(audioFile.url.path)")
            }

            let samplesPerPixel: Int = resolution.samplesPerPoint

            // analysis buffer size
            var framesPerBuffer: AVAudioFrameCount = AVAudioFrameCount(samplesPerPixel)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: framesPerBuffer
            ), buffer.frameCapacity > 0 else {
                throw NSError(description: "Unable to create buffer")
            }

            let channelCount = audioFile.fileFormat.channelCount.int

            // output data
            let outputLength = totalFrames.int / samplesPerPixel

            var floatChannelData = Array(repeating: [Float](zeros: outputLength), count: channelCount)

            func send(progress: ProgressValue1) {
                // Log.debug(progress)
                progressHandler??(progress)
            }

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

                send(progress: audioFile.framePosition.double / totalFrames.double)
            }

            send(progress: 1)

            return floatChannelData
        }

        switch await task.result {
        case let .success(value):
            return value

        case let .failure(value):
            throw value
        }
    }
}

extension WaveformDataParser {
    // The `getAudioSamples` function returns the naturtal time scale and
    // an array of single-precision values that represent an audio resource.
    public static func getAssetSamples(url: URL) async throws -> [Float] {
        let asset = AVAsset(url: url)

        let reader = try AVAssetReader(asset: asset)

        guard let track = try await asset.load(.tracks).first else {
            throw NSError(description: "didn't find an asset track")
        }

        let outputSettings: [String: Int] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsBigEndianKey: 0,
            AVLinearPCMIsFloatKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: 1,
        ]

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )

        reader.add(output)
        reader.startReading()

        var samplesData = [Float]()

        while reader.status == .reading {
            if
                let sampleBuffer = output.copyNextSampleBuffer(),
                let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let bufferLength = CMBlockBufferGetDataLength(dataBuffer)
                let count = bufferLength / 4

                let data = [Float](unsafeUninitializedCapacity: count) { buffer, initializedCount in

                    CMBlockBufferCopyDataBytes(dataBuffer,
                                               atOffset: 0,
                                               dataLength: bufferLength,
                                               destination: buffer.baseAddress!)

                    initializedCount = count
                }

                samplesData.append(contentsOf: data)
            }
        }

        return samplesData
    }
}
