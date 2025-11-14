import Foundation
import AVFoundation

public protocol AudioDeviceManagerDelegate: AnyObject {
    
    var audioEngineOutputNode: AVAudioOutputNode { get }
    var audioEngineInputNode: AVAudioInputNode? { get }
    
    func audioDeviceManager(event: AudioDeviceManager.Event)
}
