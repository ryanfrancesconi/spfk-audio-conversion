// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation

public enum AudioEditorEvent {
    case loaded(audioFile: AVAudioFile)
    case unloaded
    case play(time: TimeInterval?)
    case stop
    case update(time: TimeInterval)
    case loop(state: Bool)
}
