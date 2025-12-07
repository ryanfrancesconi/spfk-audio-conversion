// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

@preconcurrency import AVFoundation
import Foundation
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.realtime, .engine))
final class RecordTests: AudioWorkspaceTestCase {
    @Test func printDeviceInputChannels() async throws {
        guard let device = await deviceManager.selectedInputDevice else { return }

        let namedChannels = await device.namedChannels(scope: .input)

        Log.debug(device.name, "\(namedChannels.count) channel(s)", namedChannels)

        var actualNamedChannels = [AudioDeviceNamedChannel]()

        for i in 0 ..< 256 {
            let channel = UInt32(i)
            guard let name = device.name(channel: channel, scope: .input) else { break }

            actualNamedChannels.append(
                AudioDeviceNamedChannel(channel: channel, name: name, scope: .input),
            )
        }

        Log.debug("actualNamedChannels", actualNamedChannels)

        let layoutChannelDescriptions = device.layoutChannelDescriptions(scope: .input)
        Log.debug(layoutChannelDescriptions?.map(\.mCoordinates))

        guard let inputStreams = await device.streams(scope: .input) else { return }

        Log.debug(inputStreams.count, "input streams")

        for stream in inputStreams {
            let physicalFormatChannels = stream.physicalFormat?.mChannelsPerFrame ?? 0
            let virtualFormatChannels = stream.virtualFormat?.mChannelsPerFrame ?? 0

            Log.debug("physicalFormat (\(physicalFormatChannels) channels)", stream.physicalFormat)
            Log.debug("virtualFormat (\(virtualFormatChannels) channels)", stream.virtualFormat)
        }
    }

    @MainActor
    @Test func recordFromSelectedInput() async throws {
        deleteBinOnExit = false

        guard let device = await deviceManager.selectedInputDevice,
            let inputNode = await engineManager.inputNode
        else { return }

        let namedChannels = await device.namedChannels(scope: .input)
        let fileChannels = namedChannels.prefix(4).array

        let recorder = try await EngineRecorder(inputNode: inputNode, channels: fileChannels, directory: bin) {
            [weak self] event in
            _ = self
            Log.debug(event)
        }

        await recorder.update(ioLatency: deviceManager.inputDeviceLatency ?? 0)

        try engineManager.startEngine()

        // open tap
        //        try await recorder.update(recordEnabled: true)
        //        try await wait(sec: 1)

        // start recording
        try await recorder.start(channels: fileChannels)
        try await wait(sec: 2)

        await recorder.stop()

        // close tap
        try await recorder.update(recordEnabled: false)

        // results
        let fileProperties = await recorder.fileProperties

        #expect(fileChannels.count == fileProperties.count)

        for file in fileProperties {
            Log.debug(file.url.path, file.duration, "seconds written")
            #expect(file.duration.isApproximatelyEqual(to: 2, absoluteTolerance: 0.1))

            let audioFile = try AVAudioFile(forReading: file.url)
            #expect(audioFile.duration.isApproximatelyEqual(to: 2, absoluteTolerance: 0.1))
        }

        try await tearDown()
    }
}
