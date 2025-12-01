// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKBase

/// Audio Unit v3 Host for loading external Audio Units and connecting them together
public actor AudioUnitChain {
    /// The events this actor will generate
    public enum Event: Sendable {
        case connectionError(error: Error)

        case willBypass(index: Int, state: Bool)
        case didBypass(index: Int, state: Bool)

        case willRemove(index: Int)
        case didRemove(index: Int)

        case willInsert(index: Int)
        case didInsert(index: Int)

        case effectMoved(from: Int, to: Int)
    }

    /// The default amount of inserts
    public static let defaultInsertCount = 6

    /// Delegate that will be sent notifications
    public let delegate: AudioUnitChainDelegate

    /// first node in chain, generally a player or instrument
    public var input: AVAudioNode?

    /// last node in chain, generally a mixer or some kind of output
    public var output: AVAudioNode?

    public var availableAudioUnitComponents: [AVAudioUnitComponent] {
        delegate.availableAudioUnitComponents ?? []
    }

    public var data: AudioUnitChainData

    // copied here so can be referenced from synchronous contexts
    public internal(set) var effectsCount: Int = 0
    public internal(set) var effectsLatency: TimeInterval = 0

    /// flag if the entire effects chain is bypassed
    public internal(set) var isChainBypassed: Bool = false

    /// Amount of inserts available in this instance
    public private(set) var insertCount = AudioUnitChain.defaultInsertCount

    // MARK: - Initialization

    /// Create a chain with the default number of inserts
    public init(delegate: AudioUnitChainDelegate) {
        self.delegate = delegate
        data = AudioUnitChainData(insertCount: AudioUnitChain.defaultInsertCount)
    }

    /// Initialize the manager with an arbritary amount of inserts
    public init(delegate: AudioUnitChainDelegate, inserts: Int) {
        self.delegate = delegate

        data = AudioUnitChainData(insertCount: inserts)
    }

    public init(delegate: AudioUnitChainDelegate, input: AVAudioNode, output: AVAudioNode) async throws {
        self.delegate = delegate

        data = AudioUnitChainData(insertCount: AudioUnitChain.defaultInsertCount)

        try await updateIO(input: input, output: output)
    }

    public func updateIO(input: AVAudioNode, output: AVAudioNode) async throws {
        self.input = input
        self.output = output

        try await connect()
    }

    /// Clear all linked units previous processing state. IE, Panic button.
    public func reset() async {
        await data.resetAudioUnits()
    }

    // MARK: - Dispose

    /// Should be called when done with this class to release references
    public func dispose() async throws {
        try await data.removeAll()

        input = nil
        output = nil
    }
}

extension AudioUnitChain {
    public var description: String {
        get async {
            let effects = await data.linkedEffects
            let audioUnitNames: [String] = effects.compactMap(\.name)

            var value = "\(effects.count) Audio Unit\(effects.pluralString)"

            if effects.count > 0 {
                value += ": \(audioUnitNames.joined(separator: ", "))"
            }

            return value
        }
    }
}
