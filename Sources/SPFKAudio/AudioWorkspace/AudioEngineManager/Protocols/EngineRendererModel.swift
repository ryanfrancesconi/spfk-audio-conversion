// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

public protocol EngineRendererModel {
    var renderIsCanceled: Bool { get }

    func render(
        to audioFile: AVAudioFile,
        duration: TimeInterval,
        renderUntilSilent: Bool,
        prerender: (() -> Void)?,
        postrender: (() -> Void)?,
        progress progressHandler: ((UnitInterval) -> Void)?
    ) throws

    func cancelRender()
}
