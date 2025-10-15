// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFAudio
import AVFoundation
import SPFKUtils

// TODO: create incremental reader with progress events

/// Get audio data from a file suitable for waveform visualization
public enum WaveformDataRequest {
    public static func parse(
        url: URL,
        resolution: WaveformDataRequest.Resolution = .medium,
        analysisMode: AnalysisMode = .peak,
        priority: TaskPriority = .medium
    ) async throws -> FloatChannelData {
        let audioFile = try AVAudioFile(forReading: url)

        return try await parse(
            audioFile: audioFile,
            resolution: resolution,
            analysisMode: analysisMode,
            priority: priority
        )
    }

    public static func parse(
        audioFile: AVAudioFile,
        resolution: WaveformDataRequest.Resolution = .medium,
        analysisMode: AnalysisMode = .peak,
        priority: TaskPriority = .medium
    ) async throws -> FloatChannelData {
        // store the current frame
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

            let samplesPerPixel: Int = resolution.samplesPerPixel

            // analysis buffer size
            var framesPerBuffer: AVAudioFrameCount = AVAudioFrameCount(samplesPerPixel)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: framesPerBuffer
            ), buffer.frameCapacity > 0 else {
                throw NSError(description: "Unable to create buffer")
            }

            let channelCount = Int(audioFile.processingFormat.channelCount)

            // output data
            let outputLength = totalFrames.int / samplesPerPixel
            var data = Array(repeating: [Float](zeros: outputLength), count: channelCount)

            var startFrame: AVAudioFramePosition = 0

            // Log.debug("duration", audioFile.duration, "resolution", resolution, "totalFrames", totalFrames, "samplesPerPixel", samplesPerPixel, "data size", outputLength)

            for i in 0 ..< outputLength {
                audioFile.framePosition = startFrame

                try audioFile.read(into: buffer, frameCount: framesPerBuffer)

                guard let floatData = buffer.floatChannelData else {
                    throw NSError(description: "Failed to read from buffer")
                }

                let length = vDSP_Length(buffer.frameLength)

                for n in 0 ..< channelCount {
                    var value: Float = 0.0

                    if analysisMode == .peak {
                        var index: vDSP_Length = 0
                        vDSP_maxvi(floatData[n], 1, &value, &index, length)

                    } else {
                        // RMS
                        vDSP_rmsqv(floatData[n], 1, &value, length)
                    }

                    data[n][i] = value
                }

                startFrame += AVAudioFramePosition(framesPerBuffer)

                // buffer has reached end of file, trim it
                if startFrame + AVAudioFramePosition(framesPerBuffer) > totalFrames {
                    try Task.checkCancellation()

                    framesPerBuffer = totalFrames - AVAudioFrameCount(startFrame)

                    guard framesPerBuffer > 0 else { break }
                }
            }

            return data
        }

        switch await task.result {
        case let .success(value):
            return value

        case let .failure(value):
            throw value
        }
    }
}

extension WaveformDataRequest {
    public enum Resolution: CaseIterable {
        case low
        case medium
        case high
        case veryHigh

        public var samplesPerPixel: Int {
            switch self {
            case .low:
                128
            case .medium:
                64
            case .high:
                8
            case .veryHigh:
                4
            }
        }
    }
}
