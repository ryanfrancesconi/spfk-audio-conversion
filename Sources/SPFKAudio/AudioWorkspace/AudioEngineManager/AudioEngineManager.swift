import AVFoundation
import SPFKAudioHardware
import SPFKBase

public final class AudioEngineManager {
    public enum Event {
        case rebuild
        case configurationChanged
        case error(Error)
    }

    func send(event: Event) async {
        await delegate?.audioEngineManager(event: event)
    }

    public weak var delegate: AudioEngineManagerDelegate?

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

    public var allowInput: Bool {
        get async {
            await delegate?.audioEngineManagerAllowInputDevice() == true
        }
    }
    
    var renderer: EngineRenderer?

    /// Note: must call rebuildEngine before using
    public init() {}

    deinit {
        removeEngineObserver()
    }
}
