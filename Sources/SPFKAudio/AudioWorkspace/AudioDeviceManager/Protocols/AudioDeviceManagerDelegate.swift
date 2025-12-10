import Foundation
import AVFoundation

public protocol AudioDeviceManagerDelegate: Sendable {
    var audioEngineOutputNode: AVAudioOutputNode? { get }
    var audioEngineInputNode: AVAudioInputNode? { get async }
    
    func audioDeviceManager(event: AudioDeviceManager.Event) async
}
