@preconcurrency import AVFoundation
import SPFKBase

public final class AudioEngineManager: Sendable {
    public enum Event: Sendable {
        case rebuild
        case configurationChanged
        case error(Error)
    }

    func send(event: Event) async {
        await delegate.audioEngineManager(event: event)
    }

    public let engine = AVAudioEngine()

    let delegate: AudioEngineManagerDelegate
    let renderer: EngineRenderer

    /// Note: must call rebuildEngine before using
    public init(delegate: AudioEngineManagerDelegate) {
        self.delegate = delegate
        renderer = EngineRenderer(engine: engine)
    }

    deinit {
        removeEngineObserver()
    }
}
