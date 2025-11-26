// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation

public struct EngineRendererOptions: Sendable {
    /// The maximum number of PCM sample frames the engine produces in a single render call.
    let maximumFrameCount: AVAudioFrameCount

    let renderUntilSilent: Bool

    let silenceThreshold: Float

    let maxTailToRender: TimeInterval

    let disableManualRenderingModeOnCompletion: Bool

    public init(
        maximumFrameCount: AVAudioFrameCount = 4096,
        renderUntilSilent: Bool = false,
        silenceThreshold: Float = 0.00005,
        maxTailToRender: TimeInterval = TimeInterval(60 * 5),
        disableManualRenderingModeOnCompletion: Bool = true
    ) {
        self.maximumFrameCount = maximumFrameCount
        self.renderUntilSilent = renderUntilSilent
        self.silenceThreshold = silenceThreshold
        self.maxTailToRender = maxTailToRender
        self.disableManualRenderingModeOnCompletion =
            disableManualRenderingModeOnCompletion
    }
}
