import AVFoundation
import SPFKAUHost
import SPFKUtils

public final class AudioWorkspace: @unchecked Sendable {
    public private(set) lazy var engineManager = AudioEngineManager(delegate: self)

    // Note: Must call deviceManager.setup() to prepare hardware
    public private(set) lazy var deviceManager = AudioDeviceManager(delegate: self)

    public weak var delegate: AudioWorkspaceDelegate?

    // Note: must call update(cacheURL:)
    public let cacheManager = AudioUnitCacheManager(cachesDirectory: BundleProperties.cachesDirectory)

    private var outputMixer: MixerWrapper?

    // All tracks will be connected to this master
    public private(set) var masterTrack: AudioTrack?

    public init() {}

    public func setup() async throws {
        try await rebuild()
    }

    /// Rebuild the engine graph. Neceessary on startup and sample rate changes
    private func rebuild() async throws {
        Log.debug("Rebuilding engine and workspace...")

        do {
            try await shutdown()
        } catch {
            Log.error(error)
        }

        await engineManager.rebuildEngine()

        self.outputMixer = MixerWrapper()
        self.masterTrack = try await AudioTrack(delegate: self)

        guard let outputMixer, let masterTrack else {
            throw NSError(description: "Failed to create mixers on rebuild")
        }

        try await engineManager.setEngineOutput(to: outputMixer.avAudioNode)
        try await engineManager.connectAndAttach(masterTrack, to: outputMixer)
        try await deviceManager.reconnect()
    }

    private func shutdown() async throws {
        try stop()
        try masterTrack?.detachNodes()
        try await masterTrack?.audioUnitChain.dispose()
        try outputMixer?.detachNodes()
    }

    /// to be called at the app terminate
    public func dispose() async {
        do {
            try await shutdown()
        } catch {
            Log.error(error)
        }

        masterTrack = nil
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
    public func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChainEvent) {
        Log.debug(event)
    }

    public var availableAudioUnitComponents: [AVAudioUnitComponent]? {
        [] // TODO: AudioUnitCacheManager
    }

    public var audioUnitManufactererCollection: [AudioUnitManufacturerCollection] {
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
        // Log.debug("🔊", event)

        switch event {
        case .configurationChanged:
            // The AudioEngine has changed - tell the device manager to see what has
            // changed in terms of sample rates or devices. The device manager will
            // then issue its own configurationChanged eventt with an option set
            // of the changes
            await deviceManager.handleEngineConfigurationChanged()
        default:
            break
        }

        // AudioWorkspace consumes this event then reissues its own in handleConfigurationChanged
    }
}

extension AudioWorkspace: AudioDeviceManagerDelegate {
    public var audioEngineOutputNode: AVAudioOutputNode? {
        engineManager.engine?.outputNode
    }

    public var audioEngineInputNode: AVAudioInputNode? {
        get async {
            await engineManager.inputNode
        }
    }

    public func audioDeviceManager(event: AudioDeviceManager.Event) async {
        // Log.debug("🔊", event)

        switch event {
        case let .sampleRateChanged(sampleRate):
            _ = sampleRate
        case let .inputDeviceChanged(device: device):
            _ = device
        case let .outputDeviceChanged(device: device):
            _ = device
        case let .deviceListChanged(event: event):
            _ = event
            return
        case .deviceProcessorOverload:
            break
        case let .error(error):
            _ = error
        case let .configurationChanged(options):
            await handleConfigurationChanged(options: options)
        }

        await delegate?.audioWorkspace(deviceEvent: event)
    }
}

extension AudioWorkspace {
    @MainActor private func handleConfigurationChanged(options: Set<AudioDeviceManager.ConfigurationOption>) async {
        guard let delegate else { return }

        let rebuildRequired = options.contains(.sampleRateChanged)

        if rebuildRequired {
            do {
                await delegate.audioWorkspace(engineEvent: .willRebuild)
                try await rebuild()
                await delegate.audioWorkspace(engineEvent: .didRebuild)
            } catch {
                Log.error(error)

                assertionFailure(error.localizedDescription)
            }
        }

        await delegate.audioWorkspace(engineEvent: .configurationChanged)
    }
}

@MainActor
public protocol AudioWorkspaceDelegate: AnyObject {
    func audioWorkspace(deviceEvent: AudioDeviceManager.Event) async
    func audioWorkspace(engineEvent: AudioEngineManager.Event) async
}
