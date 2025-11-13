import AVFoundation
import SimplyCoreAudio
import SPFKUtils

public class AudioEngineManager {
    public enum Event {
        case rebuild
        case configurationChanged
        case error(Error)
    }

    public weak var delegate: AudioEngineManagerDelegate?

    func send(event: Event) {
        delegate?.audioEngineManager(event: event)
    }

    // MARK: -

    // AudioEngineManagerModel
    public internal(set) var engine = AVAudioEngine()

    var engineObserver: NSObjectProtocol?

    /// Will return whether the engine is rendering offline or realtime
    public var renderingMode: AVAudioEngineManualRenderingMode {
        engine.manualRenderingMode
    }

    public var isRendering: Bool {
        engine.isInManualRenderingMode
    }

    public private(set) var renderer = EngineRenderer()

    public var allowInput: Bool { delegate?.audioEngineManagerAllowInputDevice() == true }

    /// Note: must call rebuildEngine before using
    public init() {}

    deinit {
        removeEngineObserver()
    }
}
