// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Accelerate
import AVFoundation
import SPFKBase

public actor EngineRenderer {
    public let disableManualRenderingModeOnCompletion: Bool = true

    var renderTask: Task<Void, Error>?

    let engine: AVAudioEngine
    let audioFile: AVAudioFile
    let duration: TimeInterval
    let options: EngineRendererOptions

    let prerender: (() throws -> Void)?
    let postrender: (() throws -> Void)?
    let progressHandler: ((UnitInterval) -> Void)?

    public init(
        engine: AVAudioEngine,
        to audioFile: AVAudioFile,
        duration: TimeInterval,
        options: EngineRendererOptions = .init(),
        prerender: (() throws -> Void)?,
        postrender: (() throws -> Void)? = nil,
        progressHandler: ((UnitInterval) -> Void)? = nil
    ) throws {
        guard duration >= 0 else {
            throw NSError(description: "duration needs to be a positive value")
        }

        self.engine = engine
        self.audioFile = audioFile
        self.options = options
        self.duration = duration
        self.prerender = prerender
        self.postrender = postrender
        self.progressHandler = progressHandler
    }

    public func start() async throws {
        renderTask?.cancel()
        renderTask = Task<Void, Error> {
            try await process()
        }

        try await renderTask?.value

        if renderTask?.isCancelled == true {
            Log.debug("🍙⛔️ renderTask.isCancelled, attempting to remove file at \(audioFile.url.path)")
            try? audioFile.url.delete()
        }

        if disableManualRenderingModeOnCompletion,
           engine.isInManualRenderingMode
        {
            engine.disableManualRenderingMode()
        }

        Log.debug("🍙🏁 Complete")
        renderTask = nil
    }

    private func process() async throws {
        // Engine can't be running when switching to offline render mode.
        if engine.isRunning { engine.stop() }

        if !engine.isInManualRenderingMode || audioFile.processingFormat != engine.manualRenderingFormat {
            try engine.enableManualRenderingMode(
                .offline,
                format: audioFile.processingFormat,
                maximumFrameCount: options.maximumFrameCount
            )
        }

        // This resets the sampleTime of offline rendering to 0.
        engine.reset()

        Log.debug("Starting engine...")

        try engine.start()

        guard var buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        )
        else {
            throw NSError(description: "Couldn't create buffer")
        }

        // This is to prepare the nodes for playing, i.e player.play()
        try prerender?()

        // Render until file contains >= target samples
        let targetSamples = AVAudioFramePosition(
            duration * engine.manualRenderingFormat.sampleRate
        )

        var isWriting = true
        var tailTimeRendered: TimeInterval = 0
        var zeroCount = 0
        var postrenderTriggered: Bool = false

        while isWriting {
            try Task.checkCancellation()

            let isComplete = audioFile.framePosition >= targetSamples

            if !options.renderUntilSilent, isComplete {
                break
            }

            let framesToRender =
                options.renderUntilSilent
                    ? engine.manualRenderingMaximumFrameCount
                    : min(buffer.frameCapacity, AVAudioFrameCount(targetSamples - audioFile.framePosition))

            let status = try engine.renderOffline(framesToRender, to: buffer)

            // 0 - 1
            var progressValue: Double = 0

            switch status {
            case .success:
                try audioFile.write(from: buffer)
                let rawProgress = UnitInterval(audioFile.framePosition) / Double(targetSamples)
                progressValue = min(rawProgress, 1.0)
                progressHandler?(progressValue)

            case .cannotDoInCurrentContext:
                Log.error(".cannotDoInCurrentContext")
                continue

            case .insufficientDataFromInputNode:
                throw NSError(description: ".insufficientDataFromInputNode")

            case .error:
                throw NSError(
                    description:
                    "There was an error rendering to \(audioFile.url.path)"
                )

            @unknown default:
                Log.error("🍙 Unknown render result:", status)
                isWriting = false
            }

            if let postrender, isComplete, !postrenderTriggered {
                Log.debug("🍙 Triggering postrender action")
                try postrender()
                postrenderTriggered = true
            }

            if options.renderUntilSilent, progressValue == 1 {
                try Task.checkCancellation()

                guard tailTimeRendered <= options.maxTailToRender else {
                    isWriting = false
                    break
                }

                let value = try processTail(buffer: &buffer)
                tailTimeRendered += value

                if value == 0 {
                    zeroCount += 1

                    if zeroCount > 2 {
                        isWriting = false
                        Log.debug("Rendered with \(tailTimeRendered) seconds of tail")
                    }

                } else {
                    zeroCount = 0
                }
            }
        }

        Log.debug("🍙🏁 Stopping engine")

        engine.stop()
    }

    private func processTail(buffer: inout AVAudioPCMBuffer) throws -> TimeInterval {
        try Task.checkCancellation()

        let channelCount = Int(buffer.format.channelCount)

        guard let data = buffer.floatChannelData else {
            return 0
        }

        var rms: Float = 0.0

        for i in 0 ..< channelCount {
            var channelRms: Float = 0.0

            vDSP_rmsqv(data[i], 1, &channelRms, vDSP_Length(buffer.frameLength))
            rms += abs(channelRms)
        }

        let value = rms / Float(channelCount)

        guard value >= options.silenceThreshold else { return 0 }

        return TimeInterval(buffer.frameLength) / buffer.format.sampleRate
    }

    public func cancel() {
        guard let renderTask else {
            Log.error("renderTask is nil")
            return
        }

        Log.debug("🍙⛔️ Canceling...")
        renderTask.cancel()
    }

    public var isCanceled: Bool {
        renderTask?.isCancelled == true
    }
}
