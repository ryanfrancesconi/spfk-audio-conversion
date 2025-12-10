@preconcurrency import AVFoundation
import SPFKBase

public final class AudioEngineManager: @unchecked Sendable {
    public enum Event: Sendable {
        case willRebuild
        case didRebuild
        case configurationChanged
        case error(Error)
    }

    public internal(set) var engine: AVAudioEngine?

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
