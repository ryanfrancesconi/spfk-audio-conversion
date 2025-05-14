// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFAudio
import AVFoundation
import SPFKUtils

/// Get float channel data from a file suitable for waveform visualization
public struct WaveformDataRequest {
    public static func parse(
        url: URL,
        samplesPerPixel: Int,
        analysisMode: AnalysisMode = .rms,
        taper: AUValue = AutomationTaper.audio.taperUp
    ) async throws -> FloatChannelData {
        let audioFile = try AVAudioFile(forReading: url)

        return try await parse(
            audioFile: audioFile,
            samplesPerPixel: samplesPerPixel,
            analysisMode: analysisMode,
            taper: taper
        )
    }

    public static func parse(
        audioFile: AVAudioFile,
        samplesPerPixel: Int,
        analysisMode: AnalysisMode = .rms,
        taper: AUValue = AutomationTaper.audio.taperUp
    ) async throws -> FloatChannelData {
        // store the current frame
        let currentFrame = audioFile.framePosition

        defer {
            // return the file to frame is was on previously
            audioFile.framePosition = currentFrame
        }

        // prevent division by zero, + minimum resolution
        let samplesPerPixel = max(64, samplesPerPixel)
        let totalFrames = AVAudioFrameCount(audioFile.length)

        guard totalFrames > 0 else {
            throw NSError(description: "No audio was found in \(audioFile.url.path)")
        }

        var framesPerBuffer: AVAudioFrameCount = totalFrames / AVAudioFrameCount(samplesPerPixel)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(framesPerBuffer)
        ), buffer.frameCapacity > 0 else {
            throw NSError(description: "Unable to create buffer")
        }

        let channelCount = Int(audioFile.processingFormat.channelCount)
        var data = Array(repeating: [Float](zeros: samplesPerPixel), count: channelCount)
        var startFrame: AVAudioFramePosition = 0

        for i in 0 ..< samplesPerPixel {
            try Task.checkCancellation()

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
}
