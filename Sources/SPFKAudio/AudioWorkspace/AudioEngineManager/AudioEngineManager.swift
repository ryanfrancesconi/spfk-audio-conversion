import AVFoundation
import SimplyCoreAudio
import SPFKUtils

public class AudioEngineManager {
    public enum ConfigurationOption: Hashable {
        case sampleRateChanged
        case outputDeviceChanged
        case inputDeviceChanged
    }

    public enum Event {
        case configurationChanged(Set<ConfigurationOption>)
        case rebuild
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

    public var deviceManager: (any AudioDeviceManagerModel)? {
        delegate?.audioDeviceAccess
    }

    public init() {
        rebuildEngine()
    }

    deinit {
        removeEngineObserver()
    }
}
