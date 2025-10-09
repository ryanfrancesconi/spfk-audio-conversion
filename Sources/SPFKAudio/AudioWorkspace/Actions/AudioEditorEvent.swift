import AVFoundation
import Foundation

public enum AudioEditorEvent {
    case loaded(audioFile: AVAudioFile)
    case unloaded
    case play(time: TimeInterval)
    case stop
    case loop(Bool)
}
