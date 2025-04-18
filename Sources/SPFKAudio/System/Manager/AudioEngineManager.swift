import AVFoundation
import SimplyCoreAudio
import SPFKUtils

public class AudioEngineManager {
    public struct ConfigurationEvent {
        public var sampleRateChanged: Bool
        public var outputDeviceChanged: Bool
        public var inputDeviceChanged: Bool
    }

    public enum Event {
        case configuration(event: ConfigurationEvent)
        case error(Error)
    }

    public var eventHandler: ((Event) -> Void)?

    func send(event: Event) {
        eventHandler?(event)
    }

    // MARK: -

    public var _engine: AVAudioEngine = AVAudioEngine()

    var engineObserver: NSObjectProtocol?

    /// Will return whether the engine is rendering offline or realtime
    public var renderingMode: AVAudioEngineManualRenderingMode {
        engine.manualRenderingMode
    }

    public private(set) var renderer = EngineRenderer()

    public var isRendering: Bool {
        engine.isInManualRenderingMode
    }

    public var deviceManager: AudioDeviceManager

    public init(settings: DeviceSettings = DeviceSettings()) {
        deviceManager = AudioDeviceManager(settings: settings)

        // returns the current engine ref in this block
        deviceManager.engineRef = { [weak self] in self?.engine }

        rebuildEngine()
    }

    deinit {
        removeEngineObserver()
    }
}

extension AudioEngineManager {
    /// Make sure the current input device is set to a valid rate,
    /// otherwise choose a different device
    func verifyInputSampleRate() {
        guard let inputSampleRate = inputFormat?.sampleRate,
              inputSampleRate < AudioDefaults.minimumSampleRateSupported else {
            return
        }

        guard let firstCompatibleInputDevice = deviceManager.firstCompatibleInputDevice else { return }

        deviceManager.setInput(device: firstCompatibleInputDevice)

        do {
            try deviceManager.setNominalSampleRate(to: deviceManager.systemSampleRate)

        } catch {
            Log.error(error)
        }
    }
}
