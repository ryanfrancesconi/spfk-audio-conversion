// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFoundation
import OTAtomics
import OTCore
import SPFKUtils

public class EngineRenderer {
    @OTAtomicsThreadSafe private var abortFlag: Bool = false

    public var disableManualRenderingModeOnCompletion = true

    // can set this to end of timeline
    public var maxTailToRender: TimeInterval = Double(60 * 5)

    public var isCanceled: Bool {
        abortFlag == true
    }

    public func cancel() {
        abortFlag = true
    }

    public init() {}

    /// Render output to an AVAudioFile for a duration.
    ///     - Parameters
    ///         - engine: The AVAudioEngine to use
    ///         - audioFile: A file initialized for writing
    ///         - duration: Duration to render, in seconds
    ///         - renderUntilSilent: After completing rendering to the passed in duration, wait for silence. Useful
    ///         for capturing effects tails.
    ///         - silenceThreshold: Threshold value to check for silence. Default is 0.00005.
    ///         - prerender: Closure called before rendering starts, used to start players, set initial parameters, etc.
    ///         - progress: Closure called while rendering, use this to fetch render progress. 0 ... 1
    ///
    public func render(
        engine: AVAudioEngine,
        to audioFile: AVAudioFile,
        maximumFrameCount: AVAudioFrameCount = 4096,
        duration: TimeInterval,
        renderUntilSilent: Bool = false,
        silenceThreshold: Float = 0.00005,
        prerender: (() -> Void)? = nil,
        postrender: (() -> Void)? = nil,
        progress progressHandler: ((ProgressValue1) -> Void)? = nil
    ) throws {
        guard duration >= 0 else {
            throw NSError(description: "duration needs to be a positive value")
        }

        abortFlag = false

        // Engine can't be running when switching to offline render mode.
        if engine.isRunning { engine.stop() }

        if !engine.isInManualRenderingMode || audioFile.processingFormat != engine.manualRenderingFormat {
            Log.debug("🍙 Switching to ManualRenderingMode...")

            try engine.enableManualRenderingMode(
                .offline,
                format: audioFile.processingFormat,
                maximumFrameCount: maximumFrameCount
            )

            Log.debug("🍙 duration", duration, "audioFile.processingFormat", audioFile.processingFormat, "engine.manualRenderingFormat", engine.manualRenderingFormat)
        }

        // This resets the sampleTime of offline rendering to 0.
        engine.reset()

        Log.debug("Starting engine...")

        try engine.start()

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw NSError(description: "Couldn't create buffer")
        }

        // This is to prepare the nodes for playing, i.e player.play()
        prerender?()

        // Render until file contains >= target samples
        let targetSamples = AVAudioFramePosition(duration * engine.manualRenderingFormat.sampleRate)
        let channelCount = Int(buffer.format.channelCount)
        var zeroCount = 0
        var isWriting = true
        var tailTimeRendered: TimeInterval = 0

        var postrenderTriggered: Bool = false

        while isWriting {
            if abortFlag {
                Log.debug("🍙🛑 Abort detected...")
                isWriting = false
                progressHandler?(1)
            }

            let isComplete = audioFile.framePosition >= targetSamples

            if !renderUntilSilent, isComplete {
                Log.debug("🍙☑️", "Done, renderUntilSilent is false. framePosition:", audioFile.framePosition, targetSamples, "frames were rendered")
                break
            }

            let framesToRender = renderUntilSilent ?
                engine.manualRenderingMaximumFrameCount :
                min(buffer.frameCapacity, AVAudioFrameCount(targetSamples - audioFile.framePosition))

            let status = try engine.renderOffline(framesToRender, to: buffer)

            // 0 - 1
            var progressValue: Double = 0

            switch status {
            case .success:
                try audioFile.write(from: buffer)

                progressValue = min(ProgressValue1(audioFile.framePosition) / Double(targetSamples), 1.0)
                progressHandler?(progressValue)

            case .cannotDoInCurrentContext:
                Log.error(".cannotDoInCurrentContext")
                continue

            case .insufficientDataFromInputNode:
                throw NSError(description: ".insufficientDataFromInputNode")

            case .error:
                throw NSError(description: "There was an error rendering to \(audioFile.url.path)")

            @unknown default:
                Log.error("🍙 Unknown render result:", status)
                isWriting = false
            }

            if isComplete, !postrenderTriggered {
                Log.debug("🛑🍙 Triggering postrender action")
                postrender?()
                postrenderTriggered = true
            }

            if renderUntilSilent,
               progressValue == 1,
               let data = buffer.floatChannelData {
                //
                guard tailTimeRendered <= maxTailToRender else {
                    Log.error("🛑🍙 Exceeded max tail to render", tailTimeRendered, "vs", maxTailToRender)
                    isWriting = false
                    break
                }

                var rms: Float = 0.0

                for i in 0 ..< channelCount {
                    var channelRms: Float = 0.0
                    vDSP_rmsqv(data[i], 1, &channelRms, vDSP_Length(buffer.frameLength))
                    rms += abs(channelRms)
                }

                let value = rms / Float(channelCount)

                if value < silenceThreshold {
                    Log.debug("🍙 Trailing RMS \(value)")

                    zeroCount += 1

                    // check for consecutive buffers of below threshold, then assume it's silent
                    if zeroCount > 2 {
                        isWriting = false
                    }
                } else {
                    // Log.debug("🍙", "Resetting consecutive threshold check due to positive value")
                    zeroCount = 0
                }

                tailTimeRendered += buffer.frameLength.double / buffer.format.sampleRate
            }
        }

        Log.debug("🍙🏁 Stopping engine")

        engine.stop()

        if isCanceled, audioFile.url.exists {
            Log.debug("🛑🍙 User Canceled Render - Removing file at", audioFile.url.path)
            try? audioFile.url.delete()
        }

        if disableManualRenderingModeOnCompletion, engine.isInManualRenderingMode {
            Log.debug("🍙 Disabling manual rendering mode...")
            engine.disableManualRenderingMode()
        }
    }
}
