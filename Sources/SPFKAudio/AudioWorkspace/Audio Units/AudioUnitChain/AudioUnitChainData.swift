// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKBase

public actor AudioUnitChainData {
    public private(set) var effectsChain: [AudioUnitDescription?]
    public var insertCount: Int { effectsChain.count }

    /// A non nil variable length array of Audio Units that are in the chain
    public var linkedEffects: [AudioUnitDescription] {
        effectsChain.compactMap(\.self)
    }

    public var unbypassedEffects: [AudioUnitDescription] {
        linkedEffects.filter {
            !$0.isBypassed && $0.audioComponentDescription.supportsIO
        }
    }

    public var unbypassedAUAudioUnits: [AUAudioUnit] {
        unbypassedEffects.compactMap(\.avAudioUnit.auAudioUnit)
    }

    /// How many effects are active
    public var effectsCount: Int { linkedEffects.count }

    public init(insertCount: Int) {
        effectsChain = [AudioUnitDescription?](repeating: nil, count: insertCount)
    }

    public func effect(at index: Int) throws -> AudioUnitDescription? {
        try check(index: index)
        return effectsChain[index]
    }

    public func assign(audioUnitDescription: AudioUnitDescription, to index: Int) throws {
        try check(index: index)
        effectsChain[index] = audioUnitDescription
    }

    public var totalLatency: TimeInterval {
        unbypassedEffects.compactMap(\.avAudioUnit.latency).reduce(0, +)
    }

    public func latency(at index: Int) throws -> TimeInterval {
        try check(index: index)
        return try effect(at: index)?.avAudioUnit.latency ?? 0
    }

    public func isBypassed(at index: Int) throws -> Bool {
        try check(index: index)
        return effectsChain[index]?.isBypassed == true
    }

    public func bypass(index: Int) throws {
        try check(index: index)
        effectsChain[index]?.isBypassed = true
    }

    public func enable(index: Int) throws {
        try check(index: index)
        effectsChain[index]?.isBypassed = false
    }

    public func removeAll() throws {
        for i in 0 ..< effectsChain.count {
            try remove(index: i)
        }
    }

    public func remove(index: Int) throws {
        try check(index: index)
        try effectsChain[index]?.dispose()
        effectsChain[index] = nil
    }

    public func setContextName(at index: Int, string: String?) throws {
        try check(index: index)
        effectsChain[index]?.avAudioUnit.auAudioUnit.contextName = string
    }

    public func moveEffect(from startIndex: Int, to endIndex: Int) throws {
        try check(index: startIndex)
        try check(index: endIndex)

        guard let auAudioUnit = effectsChain[startIndex]?.avAudioUnit.auAudioUnit else { return }

        let bypassState = effectsChain[startIndex]?.isBypassed == true

        if !bypassState {
            effectsChain[startIndex]?.isBypassed = true
        }

        auAudioUnit.reset()

        let element = effectsChain.remove(at: startIndex)
        effectsChain.insert(element, at: endIndex)

        effectsChain[startIndex]?.isBypassed = bypassState
    }
}

extension AudioUnitChainData {
    public func resetAudioUnits() {
        for item in linkedEffects {
            item.avAudioUnit.reset()
        }
    }

    public func allocateRenderResourcesIfNeeded() async {
        for au in unbypassedAUAudioUnits where !au.renderResourcesAllocated {
            do {
                Log.debug("*AU allocateRenderResources for", au.audioUnitName)
                try au.allocateRenderResources()

            } catch {
                Log.error(error)
            }
        }
    }

    public func update(hostAUState: HostAUState) async {
        for au in unbypassedAUAudioUnits {
            if au.musicalContextBlock == nil {
                Log.debug("*AU Setting musicalContextBlock for", au.audioUnitName)
                au.musicalContextBlock = hostAUState.musicalContextBlock
            }

            if au.transportStateBlock == nil {
                Log.debug("*AU Setting transportStateBlock for", au.audioUnitName)
                au.transportStateBlock = hostAUState.transportStateBlock
            }
        }

        await allocateRenderResourcesIfNeeded()
    }
}

extension AudioUnitChainData {
    public func check(index: Int) throws {
        guard effectsChain.indices.contains(index) else { throw indexError(index: index) }
    }

    private func indexError(index: Int) -> NSError {
        NSError(description: "Invalid index requested: \(index)")
    }
}
