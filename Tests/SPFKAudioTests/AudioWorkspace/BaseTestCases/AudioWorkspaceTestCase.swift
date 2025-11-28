// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKBase
import SPFKTesting
import SPFKTime
import Testing

@testable import SPFKAudio

public class AudioWorkspaceTestCase: BinTestCase {
    public let audioWorkspace: AudioWorkspace = .init()

    var deviceManager: AudioDeviceManager { audioWorkspace.deviceManager }
    var engineManager: AudioEngineManager { audioWorkspace.engineManager }

    var audioUnitChain: AudioUnitChain? {
        audioWorkspace.master?.audioUnitChain
    }

    let auDelayDesc = AudioComponentDescription(
        componentType: 1_635_083_896,
        componentSubType: 1_684_368_505,
        componentManufacturer: 1_634_758_764,
        componentFlags: 2,
        componentFlagsMask: 0
    )

    let auMatrixReverbDesc = AudioComponentDescription(
        componentType: 1_635_083_896,
        componentSubType: 1_836_213_622,
        componentManufacturer: 1_634_758_764,
        componentFlags: 2,
        componentFlagsMask: 0
    )

    override public init() async {
        do {
            try await audioWorkspace.deviceManager.setup() // load device prefs here
        } catch {
            assertionFailure(error.localizedDescription)
        }
        await super.init()
    }

    public func setup() async throws {
        try await audioWorkspace.rebuild()
        try audioWorkspace.start()
    }

    deinit {
        do {
            try audioWorkspace.stop()
        } catch {
            Log.error(error)
        }
    }
}
