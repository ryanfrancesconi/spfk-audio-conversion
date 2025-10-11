import AVFoundation
import SimplyCoreAudio
import SPFKUtils

public class AudioEngineManager {
    // TODO: make option set
    public struct ConfigurationEvent {
        public var sampleRateChanged: Bool
        public var outputDeviceChanged: Bool
        public var inputDeviceChanged: Bool
    }

    public enum Event {
        case configuration(event: ConfigurationEvent)
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

    public var deviceManager: AudioDeviceManagerModel? {
        delegate?.audioDeviceAccess
    }

    public init() {
        rebuildEngine()
    }

    deinit {
        removeEngineObserver()
    }
}

public protocol AudioEngineManagerDelegate: AnyObject, AudioDeviceAccess {
    func audioEngineManager(event: AudioEngineManager.Event)
}
