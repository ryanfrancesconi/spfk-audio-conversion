import AVFoundation
import Foundation

public enum AudioEditorEvent {
    case loaded(audioFile: AVAudioFile)
    case unloaded
    case play(time: TimeInterval?)
    case stop
    case update(time: TimeInterval)
    case loop(Bool)
}
