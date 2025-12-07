// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Accelerate
import AVFoundation
import SPFKBase
import SPFKSoX

public actor EngineRenderer {
    let engine: AVAudioEngine

    var disableManualRenderingModeOnCompletion: Bool = true
    var renderTask: Task<Void, Error>?

    var audioFile: AVAudioFile?
    var duration: TimeInterval = 0
    var options: EngineRendererOptions = .init()
    var prerender: (@Sendable () throws -> Void)?
    var postrender: (@Sendable () throws -> Void)?
    var progressHandler: (@Sendable (UnitInterval) -> Void)?

    private var targetSamples: AVAudioFramePosition = 0

    var maxFramePerSlice: AVAudioFrameCount {
        engine.outputNode.auAudioUnit.maximumFramesToRender
    }

    var manualRenderingFormat: AVAudioFormat {
        audioFile?.processingFormat ?? engine.manualRenderingFormat
    }

    public init(engine: AVAudioEngine) {
        self.engine = engine
    }
}

extension EngineRenderer: EngineRendererModel {
    public func render(
        to audioFile: AVAudioFile,
        duration: TimeInterval,
        options: EngineRendererOptions = .init(),
        prerender: @escaping @Sendable () throws -> Void, // play()
        postrender: (@Sendable () throws -> Void)?, // stop()
        progressHandler: (@Sendable (UnitInterval) -> Void)? = nil,
        disableManualRenderingModeOnCompletion: Bool = true
    ) async throws {
        guard duration > 0 else {
            throw NSError(description: "duration needs to be a positive value")
        }

        self.audioFile = audioFile
        self.options = options
        self.duration = duration
        self.prerender = prerender
        self.postrender = postrender
        self.progressHandler = progressHandler
        self.disableManualRenderingModeOnCompletion = disableManualRenderingModeOnCompletion

        try await start()
    }

    public func cancelRender() async {
        guard let renderTask else {
            Log.error("renderTask is nil")
            return
        }

        Log.debug("🍙⛔️ Canceling...")

        renderTask.cancel()
    }
}

extension EngineRenderer {
    private func start() async throws {
        guard let audioFile else {
            throw NSError(description: "audioFile is nil")
        }

        renderTask?.cancel()
        renderTask = Task<Void, Error> {
            try await setupEngine()
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

    private func setupEngine() async throws {
        guard let audioFile else {
            throw NSError(description: "audioFile is nil")
        }

        defer {
            Log.debug("🍙🏁 Stopping engine, wrote", audioFile.duration, "seconds to file")
            engine.stop()
        }

        // Engine can't be running when switching to offline render mode.
        engine.stop()

        if !engine.isInManualRenderingMode || audioFile.processingFormat != engine.manualRenderingFormat {
            let maxFrameCount: AVAudioFrameCount = UInt32(duration * audioFile.processingFormat.sampleRate) / 100

            try engine.enableManualRenderingMode(
                .offline,
                format: manualRenderingFormat,
                maximumFrameCount: maxFrameCount
            )
        }

        assert(engine.manualRenderingFormat == audioFile.processingFormat)

        // This resets the sampleTime of offline rendering to 0.
        engine.reset()

        Log.debug("Starting engine...")

        try engine.start()

        try write()
    }

    private func write() throws {
        guard let audioFile else {
            throw NSError(description: "audioFile is nil")
        }

        guard let prerender else {
            throw NSError(description: "prerender is nil")
        }

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: engine.manualRenderingMaximumFrameCount
            )
        else {
            throw NSError(description: "Couldn't create buffer with format \(engine.manualRenderingFormat)")
        }

        // MARK: - Render Loop

        targetSamples = AVAudioFramePosition(
            duration * manualRenderingFormat.sampleRate
        )

        assert(targetSamples > 0)

        // This is to prepare the nodes for playing, i.e player.play()
        try prerender()

        while engine.manualRenderingSampleTime < targetSamples {
            let frameCount = targetSamples - engine.manualRenderingSampleTime
            let framesToRender = min(AVAudioFrameCount(frameCount), buffer.frameCapacity)
            try write(buffer: buffer, framesToRender: framesToRender)

            let rawProgress = UnitInterval(audioFile.framePosition) / Double(targetSamples)

            progressHandler?(
                min(rawProgress, 1.0)
            )

            let isComplete = rawProgress >= 1

            if isComplete {
                break
            }
        }

        // MARK: - Stop

        if let postrender {
            Log.debug("🍙 Triggering postrender action")
            try postrender()
        }

        if options.renderUntilSilent {
            try writeTail()
        }
    }

    private func write(buffer: AVAudioPCMBuffer, framesToRender: AVAudioFrameCount) throws {
        guard let audioFile else {
            throw NSError(description: "audioFile is nil")
        }

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
}

// MARK: - Tail Loop

extension EngineRenderer {
    private func writeTail() throws {
        Log.debug("Entering audio tail loop...")

        let framesToRender: AVAudioFrameCount = maxFramePerSlice

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: framesToRender
            )
        else {
            throw NSError(description: "Couldn't create buffer with format \(engine.manualRenderingFormat)")
        }

        var silenceRendered: TimeInterval = 0
        var zerosRendered: TimeInterval = 0

        while true {
            try Task.checkCancellation()

            try write(buffer: buffer, framesToRender: framesToRender)

            let rms = try rms(for: buffer)

            if rms < options.silenceThreshold {
                silenceRendered += (Double(buffer.frameLength) / buffer.format.sampleRate)

                if rms == 0 {
                    zerosRendered = silenceRendered
                }

                if zerosRendered > options.zeroSilenceQuantity { break }

                if silenceRendered > options.underSilenceThresholdQuantity { break }
                if silenceRendered > options.maxTailToRender { break }
            }
        }

        Log.debug("Rendered an extra", silenceRendered, "seconds")
    }

    private func rms(for buffer: AVAudioPCMBuffer) throws -> Float {
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

        return value
    }
}
