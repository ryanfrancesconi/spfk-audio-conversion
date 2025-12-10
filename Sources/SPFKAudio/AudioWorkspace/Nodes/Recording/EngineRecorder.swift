// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

@preconcurrency import AVFoundation
import SPFKAudioHardware
import SPFKBase

public final class EngineRecorder: Sendable {
    let recorder: MultiChannelInputNodeTap

    public let directory: URL

    public var fileProperties: [WriteableFileProperties] {
        get async {
            await recorder.fileProperties
        }
    }

    public let channels: [AudioDeviceNamedChannel]

    let eventHandler: (@Sendable (MultiChannelInputNodeTap.Event) -> Void)?

    public init(
        inputNode: AVAudioInputNode,
        channels: [AudioDeviceNamedChannel],
        directory: URL,
        eventHandler: (@Sendable (MultiChannelInputNodeTap.Event) -> Void)? = nil
    ) async throws {
        guard await AudioDeviceManager.requestAccess(for: .audio) else {
            throw NSError(description: "Audio input access was denied")
        }

        self.channels = channels
        self.directory = directory
        self.eventHandler = eventHandler

        recorder = MultiChannelInputNodeTap(
            inputNode: inputNode, directory: directory, delegate: nil,
        )

        await recorder.update(delegate: self)

        try await recorder.prepare(fileChannels: channels)
    }

    deinit {
        Log.debug("- { \(self) }")
    }

    public func update(ioLatency: AVAudioFrameCount) async {
        await recorder.update(ioLatency: ioLatency)
    }

    public func update(recordEnabled newValue: Bool) async throws {
        try await recorder.update(recordEnabled: newValue)
    }

    public func start(channels: [AudioDeviceNamedChannel]) async throws {
        try await recorder.prepare(fileChannels: channels)
        try await update(recordEnabled: true)
        try await recorder.record()
    }

    public func stop() async {
        await recorder.stop()
    }
}

extension EngineRecorder: MultiChannelInputNodeTapDelegate {
    public func multiChannelInputNodeTap(event: MultiChannelInputNodeTap.Event) {
        eventHandler?(event)
    }
}
