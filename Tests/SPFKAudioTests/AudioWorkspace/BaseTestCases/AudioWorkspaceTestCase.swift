// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAUHost
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
        audioWorkspace.masterTrack?.audioUnitChain
    }

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

    func tearDown() async throws {
        try audioWorkspace.stop()
        await audioWorkspace.dispose()
    }
}
