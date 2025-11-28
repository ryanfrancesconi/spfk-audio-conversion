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

    let prerender: @Sendable () throws -> Void
    let postrender: (@Sendable () throws -> Void)?
    let progressHandler: (@Sendable (UnitInterval) -> Void)?

    private var targetSamples: AVAudioFramePosition = 0

    public init(
        engine: AVAudioEngine,
        to audioFile: AVAudioFile,
        duration: TimeInterval,
        options: EngineRendererOptions = .init(),
        prerender: @escaping @Sendable () throws -> Void, // play()
        postrender: (@Sendable () throws -> Void)?, // stop()
        progressHandler: (@Sendable (UnitInterval) -> Void)? = nil
    ) throws {
        guard duration > 0 else {
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

    deinit {
        Log.debug("- { \(self) }")
    }

    public func start() async throws {
        renderTask?.cancel()
        // Ensure the Task’s closure is main-actor isolated so it does not “send” self.
        renderTask = Task<Void, Error> {
            try await process()
        }

        defer {
            if disableManualRenderingModeOnCompletion, engine.isInManualRenderingMode {
                engine.disableManualRenderingMode()
            }

            Log.debug("🍙🏁 Complete")
            renderTask = nil
        }

        guard let renderTask else { return }

        let result = await renderTask.result

        guard !renderTask.isCancelled else {
            Log.debug("🍙⛔️ renderTask.isCancelled, attempting to remove file at \(audioFile.url.path)")
            try? audioFile.url.delete()
            throw CancellationError()
        }

        switch result {
        case .success:
            Log.debug("🍙 OK, rendered \(audioFile.length) samples")

        case let .failure(error):
            throw error
        }
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

        // don't check sample rate until the engine is in manual mode
        targetSamples = AVAudioFramePosition(
            duration * engine.manualRenderingFormat.sampleRate
        )

        assert(targetSamples > 0)

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
        try prerender()

        var tailTimeRendered: TimeInterval = 0
        var zeroCount = 0

        while true {
            try Task.checkCancellation()

            let isComplete = audioFile.framePosition >= targetSamples
            try write(buffer: &buffer)

            let rawProgress = UnitInterval(audioFile.framePosition) / Double(targetSamples)

            progressHandler?(
                min(rawProgress, 1.0)
            )

            guard isComplete else { continue }

            if let postrender {
                Log.debug("🍙 Triggering postrender action")
                try postrender()
            }

            guard options.renderUntilSilent else {
                break
            }

            try Task.checkCancellation()

            guard tailTimeRendered <= options.maxTailToRender else {
                Log.error("tailTimeRendered (\(tailTimeRendered)) > options.maxTailToRender (\(options.maxTailToRender))")
                break
            }

            let value = try processTail(buffer: &buffer)
            tailTimeRendered += value

            if value == 0 {
                zeroCount += 1

                if zeroCount > 2 {
                    Log.debug("Rendered with \(tailTimeRendered) seconds of tail")
                    break
                }

            } else {
                zeroCount = 0
            }
        }

        Log.debug("🍙🏁 Stopping engine, wrote", audioFile.duration, "seconds to file")

        engine.stop()
    }

    private func write(buffer: inout AVAudioPCMBuffer) throws {
        let framesToRender = options.renderUntilSilent ?
            engine.manualRenderingMaximumFrameCount :
            min(buffer.frameCapacity, AVAudioFrameCount(targetSamples - audioFile.framePosition))

        let status = try engine.renderOffline(framesToRender, to: buffer)

        switch status {
        case .success:
            try audioFile.write(from: buffer)

        case .cannotDoInCurrentContext:
            throw NSError(description: ".cannotDoInCurrentContext")

        case .insufficientDataFromInputNode:
            throw NSError(description: ".insufficientDataFromInputNode")

        case .error:
            throw NSError(description: "There was an error rendering to \(audioFile.url.path)")

        @unknown default:
            throw NSError(description: "Unknown render result: \(status)")
        }
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
}
