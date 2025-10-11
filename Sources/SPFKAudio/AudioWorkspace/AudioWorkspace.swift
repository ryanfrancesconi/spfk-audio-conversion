import AVFoundation
import SPFKUtils

public class AudioWorkspace {
    public private(set) lazy var engineManager: AudioEngineManager = {
        var engineManager = AudioEngineManager()
        engineManager.delegate = self
        return engineManager
    }()

    public private(set) lazy var deviceManager: AudioDeviceManager = {
        var deviceManager = AudioDeviceManager( /* settings: persistentState */ )
        deviceManager.delegate = self
        return deviceManager
    }()

    public let cacheManager = AudioUnitCacheManager(cachesDirectory: BundleProperties.cachesDirectory)

    private var outputMixer: MixerWrapper?

    // All tracks will be connected to this master
    public private(set) var master: AudioTrack?

    // settings: persistentState
    public init() {}

    /// Rebuild the engine graph. Neceessary on startup and sample rate changes
    public func rebuild() async throws {
        try await shutdown()

        engineManager.rebuildEngine()

        self.outputMixer = MixerWrapper()
        self.master = try await AudioTrack(delegate: self)

        guard let outputMixer, let master else {
            return
        }

        try engineManager.setEngineOutput(to: outputMixer.avAudioNode)
        try engineManager.connectAndAttach(master, to: outputMixer)
    }

    public func shutdown() async throws {
        try stop()

        try master?.detachNodes()
        try await master?.audioUnitChain.dispose()

        try outputMixer?.detachNodes()
    }

    public func start() throws {
        try engineManager.startEngine()
    }

    public func stop() throws {
        if engineManager.engineIsRunning {
            engineManager.stopEngine()
        }
    }
}

extension AudioWorkspace: AudioTrackDelegate {}

extension AudioWorkspace: AudioEngineConnection {
    public func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) throws {
        try engineManager.connectAndAttach(node1, to: node2, format: format)
    }
}

extension AudioWorkspace: AudioUnitChainDelegate {
    public func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChain.Event) {
        Log.debug(event)
    }

    public var availableAudioUnitComponents: [AVAudioUnitComponent]? {
        [] // TODO: AudioUnitCacheManager
    }
}

extension AudioWorkspace: AudioEngineAccess {
    public var audioEngineAccess: (any AudioEngineManagerModel)? { engineManager }
}

extension AudioWorkspace: AudioDeviceAccess {
    public var audioDeviceAccess: (any AudioDeviceManagerModel)? { deviceManager }
}

extension AudioWorkspace: AudioEngineManagerDelegate {
    // TODO: handle events
    public func audioEngineManager(event: AudioEngineManager.Event) {
        switch event {
        case let .configurationChanged(options):
            Log.debug(options)

        case let .error(error):
            Log.error(error)

        case .rebuild:
            // deviceManager
            break
        }
    }
}

extension AudioWorkspace: AudioDeviceManagerDelegate {
    public func audioDeviceManager(event: AudioDeviceManager.Event) {
        Log.debug(event)
    }
}
