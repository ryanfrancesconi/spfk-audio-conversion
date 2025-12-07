// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioHardware
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudio

@Suite(.serialized, .tags(.realtime, .engine))
final class AudioWorkspaceTests: AudioWorkspaceTestCase {
    var dm: AudioDeviceManager { audioWorkspace.deviceManager }
    var em: AudioEngineManager { audioWorkspace.engineManager }
}
