import AVFoundation
import SPFKUtils

public class AudioWorkspace {
    public private(set) lazy var engineManager: AudioEngineManager = {
        var engineManager = AudioEngineManager()
        engineManager.delegate = self
        return engineManager
    }()

    // Must call deviceManager.setup() to prepare hardware
    public private(set) lazy var deviceManager: AudioDeviceManager = {
        var deviceManager = AudioDeviceManager()
        deviceManager.delegate = self
        return deviceManager
    }()

    public weak var delegate: AudioWorkspaceDelegate?

    public let cacheManager = AudioUnitCacheManager(cachesDirectory: BundleProperties.cachesDirectory)

    private var outputMixer: MixerWrapper?

    // All tracks will be connected to this master
    public private(set) var master: AudioTrack?

    public init() {}

    /// Rebuild the engine graph. Neceessary on startup and sample rate changes
    public func rebuild() async throws {
        try await shutdown()

        await engineManager.rebuildEngine()

        self.outputMixer = MixerWrapper()
        self.master = try await AudioTrack(delegate: self)

        guard let outputMixer, let master else {
            throw NSError(description: "Failed to create mixers on rebuild")
        }

        try await engineManager.setEngineOutput(to: outputMixer.avAudioNode)
        try await engineManager.connectAndAttach(master, to: outputMixer)

        try await deviceManager.reconnect()
    }

    private func shutdown() async throws {
        try stop()
        engineManager.removeEngineObserver()

        try master?.detachNodes()
        try await master?.audioUnitChain.dispose()

        try outputMixer?.detachNodes()
    }

    /// to be called at the app terminate
    public func dispose() async {
        do {
            try await shutdown()
        } catch {
            Log.error(error)
        }

        master = nil
        outputMixer = nil
        
        do {
            try await deviceManager.dispose()
        } catch {
            Log.error(error)
        }
    }

    public var isRunning: Bool { engineManager.engineIsRunning }

    public func start() throws {
        if !isRunning {
            try engineManager.startEngine()
        }
    }

    public func stop() throws {
        if isRunning {
            engineManager.stopEngine()
        }
    }
}

extension AudioWorkspace: AudioTrackDelegate {}

extension AudioWorkspace: AudioEngineConnection {
    public func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) async throws {
        try await engineManager.connectAndAttach(node1, to: node2, format: format)
    }
}

extension AudioWorkspace: AudioUnitChainDelegate {
    public func audioUnitChain(_: AudioUnitChain, event: AudioUnitChain.Event) {
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
    public func audioEngineManagerAllowInputDevice() async -> Bool {
        await deviceManager.allowInput
    }

    public func audioEngineManager(event: AudioEngineManager.Event) async {
        Log.debug(event)

        switch event {
        case let .error(error):
            Log.error(error)

        case .rebuild:
            break

        case .configurationChanged:
            await deviceManager.handleEngineConfigurationChanged()
        }
    }
}

extension AudioWorkspace: AudioDeviceManagerDelegate {
    public var audioEngineOutputNode: AVAudioOutputNode {
        engineManager.engine.outputNode
    }

    public var audioEngineInputNode: AVAudioInputNode? {
        get async {
            await engineManager.inputNode
        }
    }

    @MainActor public func audioDeviceManager(event: AudioDeviceManager.Event) async {
        Log.debug("🔊", event)

        switch event {
        case let .sampleRateChanged(sampleRate):
            _ = sampleRate
        case let .inputDeviceChanged(device: device):
            _ = device
        case let .outputDeviceChanged(device: device):
            _ = device
        case let .deviceListChanged(event: event):
            _ = event
        case .deviceProcessorOverload:
            break
        case let .error(error):
            _ = error
        case let .configurationChanged(options):
            do {
                try handleConfigurationChanged(options: options)
            } catch {
                Log.error(error)
            }
        }
    }
}

extension AudioWorkspace {
    func handleConfigurationChanged(options: Set<AudioDeviceManager.ConfigurationOption>) throws {
        if options.contains(.sampleRateChanged) {
            delegate?.audioWorkspaceShouldRebuild(self)

        } else {
            delegate?.audioWorkspaceShouldRestart(self)
        }
    }
}

public protocol AudioWorkspaceDelegate: AnyObject {
    func audioWorkspaceShouldRebuild(_ audioWorkspace: AudioWorkspace)
    func audioWorkspaceShouldRestart(_ audioWorkspace: AudioWorkspace)
}
