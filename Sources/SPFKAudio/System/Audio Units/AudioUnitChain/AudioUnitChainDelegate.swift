

public protocol AudioUnitChainDelegate: EngineAccess, AudioUnitAvailability {
    func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChain.Event)
}
