import AVFoundation
import SPFKUtils

public class AudioWorkspace {
    public private(set) lazy var engineManager: AudioEngineManager = {
        var engineManager = AudioEngineManager( /* settings: persistentState */ )

        engineManager.eventHandler = { [weak self] event in
            guard let self else { return }

            switch event {
            case let .configuration(event: event):
                Log.debug(event)

            case let .error(error):
                Log.error(error)
            }
        }

        return engineManager
    }()

    private var outputMixer: MixerWrapper?

    // All tracks will be connected to this master
    public private(set) var master: AudioTrack?

    public init() {}

    /// Rebuild the engine graph. Neceessary on sample rate changes
    public func rebuild() async throws {
        try await shutdown()

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

extension AudioWorkspace: AudioTrackDelegate {
}

extension AudioWorkspace: AudioUnitChainDelegate {
    public func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChain.Event) {
        Log.debug(event)
    }

    public var audioEngineAccess: (any AudioEngineManagerModel)? { engineManager }

    public var availableAudioUnitComponents: [AVAudioUnitComponent]? {
        [] // TODO:
    }
}
