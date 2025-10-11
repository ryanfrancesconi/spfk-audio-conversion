// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

public protocol AudioUnitChainDelegate: AudioEngineConnection, AudioUnitAvailability {
    func audioUnitChain(_ audioUnitChain: AudioUnitChain, event: AudioUnitChain.Event)
}

