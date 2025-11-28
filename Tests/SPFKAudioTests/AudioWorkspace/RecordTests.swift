// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@Suite(.serialized, .tags(.realtime, .engine))
final class RecordTests: AudioWorkspaceTestCase {


    @Test func printDeviceInputChannels() async throws {
        guard let device = await deviceManager.selectedInputDevice else { return }

        let namedChannels = await device.namedChannels(scope: .input)

        let channelCount = await device.channels(scope: .input)

        Log.debug(device.name, "\(channelCount) channel(s)", namedChannels)

        //            for i in 0 ..< 33 {
        //                guard let name = device.name(channel: UInt32(i), scope: .input) else { continue }
        //
        //                Log.debug(name)
        //            }

        guard let streams = await device.streams(scope: .input) else { return }

        for stream in streams {
            Log.debug("physicalFormat", stream.physicalFormat, "virtualFormat", stream.virtualFormat)
        }

        //            let names = await device.channels(scope: .input)
    }
}
