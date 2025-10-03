import AVFoundation
import SPFKUtils

public protocol EngineRendererModel {
    var renderIsCanceled: Bool { get }

    func render(
        to audioFile: AVAudioFile,
        duration: Double,
        renderUntilSilent: Bool,
        prerender: (() -> Void)?,
        postrender: (() -> Void)?,
        progress progressHandler: ((ProgressValue1) -> Void)?
    ) throws

    func cancelRender()
}
