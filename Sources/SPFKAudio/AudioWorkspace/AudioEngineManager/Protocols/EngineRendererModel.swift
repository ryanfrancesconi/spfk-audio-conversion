// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public protocol EngineRendererModel {
    func render(
        to audioFile: AVAudioFile,
        duration: Double,
        options: EngineRendererOptions,
        prerender: @escaping (@Sendable () throws -> Void),
        postrender: (@Sendable () throws -> Void)?,
        progressHandler: (@Sendable (UnitInterval) -> Void)?,
        disableManualRenderingModeOnCompletion: Bool
    ) async throws

    func cancelRender() async
}

extension EngineRendererModel {
    public func render(
        to url: URL,
        settings: [String: Any],
        duration: Double,
        options: EngineRendererOptions,
        prerender: @escaping (@Sendable () throws -> Void),
        postrender: (@Sendable () throws -> Void)?,
        progressHandler: (@Sendable (UnitInterval) -> Void)?,
        disableManualRenderingModeOnCompletion: Bool
    ) async throws {
        let audioFile = try AVAudioFile(forWriting: url, settings: settings)

        try await render(
            to: audioFile,
            duration: duration,
            options: options,
            prerender: prerender,
            postrender: postrender,
            progressHandler: progressHandler,
            disableManualRenderingModeOnCompletion: disableManualRenderingModeOnCompletion
        )
    }
}
