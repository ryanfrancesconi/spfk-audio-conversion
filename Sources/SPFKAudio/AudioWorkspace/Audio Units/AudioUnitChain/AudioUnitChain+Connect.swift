// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AudioToolbox
import AVFoundation
import SPFKUtils

extension AudioUnitChain {
    /// Removes all effects from the effectsChain and detach Audio Units from the engine
    public func removeEffects(reconnectChain: Bool = true, sendEvent: Bool = true) async throws {
        try await data.removeAll()

        if reconnectChain {
            try await connect()
        }
    }

    public func removeEffect(at index: Int, reconnectChain: Bool = true, sendEvent: Bool = true) async throws {
        if sendEvent {
            delegate?.audioUnitChain(self, event: .willRemove(index: index))
        }

        try await data.remove(index: index)

        if reconnectChain {
            try await connect()
        }

        if sendEvent {
            delegate?.audioUnitChain(self, event: .didRemove(index: index))
        }
    }

    /// Bypass entire effects chain
    public func bypassEffects(state: Bool) async throws {
        guard await data.effectsCount > 0 else { return }

        isChainBypassed = state

        try await connect()
    }

    public func bypassEffect(at index: Int, state: Bool, reconnect: Bool) async throws {
        delegate?.audioUnitChain(self, event: .willBypass(index: index, state: state))

        try await state ?
            data.bypass(index: index) :
            data.enable(index: index)

        if reconnect {
            try await connect()
        }

        delegate?.audioUnitChain(self, event: .didBypass(index: index, state: state))
    }

    public func moveEffect(from startIndex: Int, to endIndex: Int) async throws {
        try await data.moveEffect(from: startIndex, to: endIndex)
        try await connect()
        delegate?.audioUnitChain(self, event: .effectMoved(from: startIndex, to: endIndex))
    }

    /// Main effects chain connection method
    /// Called from client to hook the chain together
    /// firstNode would be something like a player, and last something like a mixer that's headed
    /// to the output.
    /// - Parameters:
    ///   - firstNode: optional assign initial input node
    ///   - lastNode: final output node
    public func connect() async throws {
        guard let input else {
            throw NSError(description: "input is nil - no connection will be made")
        }

        guard let output else {
            throw NSError(description: "output is nil - no connection will be made")
        }

        let unbypassedEffects = await data.unbypassedEffects

        // if there are no fx or the chain is bypassed connect input to output directly
        if isChainBypassed || unbypassedEffects.isEmpty {
            try connect(input, to: output)
            return
        }

        guard let firstEffect = unbypassedEffects.first else {
            assertionFailure("the first effect shouldn't be nil here")
            throw NSError(description: "Connection error in audio unit chain")
        }

        guard let lastEffect = unbypassedEffects.last else {
            assertionFailure("the final effect shouldn't be nil here")
            throw NSError(description: "Connection error in audio unit chain")
        }

        Log.debug("🔌 Connecting \(unbypassedEffects.count) unbypassed, \(await data.linkedEffects.count) total.")

        // connect the input to the first effect
        try connect(input, to: firstEffect.avAudioUnit)

        // if there are more effects, loop and connect them
        if unbypassedEffects.count > 1 {
            for i in 1 ..< unbypassedEffects.count {
                let auInput = unbypassedEffects[i - 1].avAudioUnit
                let auOutput = unbypassedEffects[i].avAudioUnit

                Log.debug("Connecting", auInput.name, "to", auOutput.name)

                try connect(auInput, to: auOutput)
            }
        }

        // connect the last effect (which could also be the first) to the output
        try connect(lastEffect.avAudioUnit, to: output)

        await data.allocateRenderResourcesIfNeeded()

        // NOTE: copy values out of concurrency

        effectsCount = await data.effectsCount
        effectsLatency = await data.totalLatency
    }

    private func connect(_ firstNode: AVAudioNode, to secondNode: AVAudioNode) throws {
        guard let audioEngineAccess else {
            throw NSError(description: "engine manager is nil")
        }

        try audioEngineAccess.connectAndAttach(
            firstNode,
            to: secondNode
        )
    }
}
