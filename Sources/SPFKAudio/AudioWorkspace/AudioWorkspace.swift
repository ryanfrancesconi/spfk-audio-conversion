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

    var masterMixer: MixerWrapper?

    var masterAudioUnitChain: AudioUnitChain?

    var masterFader: Fader?

    public init() {
    }

    /// Rebuild the engine graph. Neceessary on sample rate changes
    public func rebuild() async throws {
        try shutdown()

        let outputMixer = MixerWrapper()
        try engineManager.setEngineOutput(to: outputMixer.avAudioNode)

        let masterFader = try await Fader()
        try engineManager.connectAndAttach(masterFader, to: outputMixer)

        let masterMixer = MixerWrapper()
        let masterAudioUnitChain = try await AudioUnitChain(input: masterMixer.avAudioNode, output: masterFader.avAudioNode, delegate: self)

        //
        self.outputMixer = outputMixer
        self.masterFader = masterFader
        self.masterMixer = masterMixer
        self.masterAudioUnitChain = masterAudioUnitChain
    }

    func shutdown() throws {
        try stop()

        try masterFader?.detachNodes()
        try masterMixer?.detachNodes()
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

extension AudioWorkspace: AudioUnitChainDelegate {
    public func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChain.Event) {
        Log.debug(event)
    }

    public func engineAccess() -> (any AudioEngineManagerModel)? { engineManager }

    public var availableAudioUnitComponents: [AVAudioUnitComponent]? {
        []
    }
}
