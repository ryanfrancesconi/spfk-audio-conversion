@preconcurrency import AVFoundation
import SPFKBase

public final class AudioEngineManager: @unchecked Sendable {
    public enum Event: Sendable {
        case rebuild
        case configurationChanged
        case error(Error)
    }

    func send(event: Event) async {
        await delegate.audioEngineManager(event: event)
    }

    public var engine: AVAudioEngine?
    var renderer: EngineRenderer?

    let delegate: AudioEngineManagerDelegate

    var engineConfigurationObserver: NSObjectProtocol?
    
    /// Note: must call rebuildEngine before using
    public init(delegate: AudioEngineManagerDelegate) {
        self.delegate = delegate
    }

    deinit {
        removeEngineObserver()

        Log.debug("- { \(self) }")
    }
}
