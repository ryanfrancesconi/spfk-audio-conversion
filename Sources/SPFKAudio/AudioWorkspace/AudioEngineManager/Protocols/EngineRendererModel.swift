// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public protocol EngineRendererModel {
    func cancelRender() async

    func render(
        to audioFile: AVAudioFile,
        duration: Double,
        options: EngineRendererOptions,
        prerender: @escaping (() throws -> Void),
        postrender: @escaping (() throws -> Void),
        progressHandler: ((UnitInterval) -> Void)?
    ) async throws
}
