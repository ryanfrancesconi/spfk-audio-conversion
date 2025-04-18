//  Copyright © 2020 Audio Design Desk. All rights reserved.

import Accelerate
import AVFAudio
import AVFoundation
import OTCore
import SPFKUtils

/// Get float channel data from a file suitable for visualization
public struct WaveformDataRequest {
    /// Determines if the returned amplitude value is the rms or peak value
    public var analysisMode: AnalysisMode = .rms
    public var taper: AUValue = FadeDescription.AudioTaper.taper.in

    private var dataTask: Task<FloatChannelData, Error>?

    public init() {}

    public mutating func getData(url: URL, samplesPerPixel: Int) async throws -> FloatChannelData {
        let audioFile = try AVAudioFile(forReading: url)
        return try await getData(audioFile: audioFile, samplesPerPixel: samplesPerPixel)
    }

    public mutating func getData(audioFile: AVAudioFile, samplesPerPixel: Int, analysisMode: AnalysisMode? = nil, taper: AUValue? = nil) async throws -> FloatChannelData {
        // store the current frame
        let currentFrame = audioFile.framePosition

        let analysisMode = analysisMode ?? self.analysisMode
        let taper = taper ?? self.taper

        defer {
            // return the file to frame is was on previously
            audioFile.framePosition = currentFrame
        }

        dataTask?.cancel()
        dataTask = Task<FloatChannelData, Error> {
            // prevent division by zero, + minimum resolution
            let samplesPerPixel = max(64, samplesPerPixel)

            let totalFrames = AVAudioFrameCount(audioFile.length)
            var framesPerBuffer: AVAudioFrameCount = totalFrames / AVAudioFrameCount(samplesPerPixel)

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(framesPerBuffer)
            ) else {
                throw NSError(description: "Unable to create buffer")
            }

            let channelCount = Int(audioFile.processingFormat.channelCount)
            var data = Array(repeating: [Float](zeros: samplesPerPixel), count: channelCount)
            var startFrame: AVAudioFramePosition = 0

            for i in 0 ..< samplesPerPixel {
                if Task.isCancelled {
                    // return the file to frame is was on previously
                    audioFile.framePosition = currentFrame
                    throw NSError(description: "Cancelling waveform data")
                }

                audioFile.framePosition = startFrame
                try audioFile.read(into: buffer, frameCount: framesPerBuffer)

                guard let floatData = buffer.floatChannelData else {
                    throw NSError(description: "Buffer is nil on read")
                }

                let length = vDSP_Length(buffer.frameLength)

                for n in 0 ..< channelCount {
                    var value: Float = 0.0

                    if analysisMode == .peak {
                        var index: vDSP_Length = 0
                        vDSP_maxvi(floatData[n], 1, &value, &index, length)

                    } else {
                        vDSP_rmsqv(floatData[n], 1, &value, length)
                    }

                    data[n][i] = value.normalized(from: 0 ... 1, taper: taper)
                }

                startFrame += AVAudioFramePosition(framesPerBuffer)

                if startFrame + AVAudioFramePosition(framesPerBuffer) > totalFrames {
                    framesPerBuffer = totalFrames - AVAudioFrameCount(startFrame)
                    if framesPerBuffer <= 0 { break }
                }
            }

            return data
        }

        guard let data = try await dataTask?.value else {
            throw NSError(description: "Data returned nil")
        }

        dataTask = nil

        return data
    }

    public func cancel() {
        dataTask?.cancel()
    }
}
