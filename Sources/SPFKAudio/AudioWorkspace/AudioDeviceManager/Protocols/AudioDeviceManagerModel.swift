import AVFoundation
import Foundation
import SPFKAudioHardware

/// Primary audio device access
public protocol AudioDeviceManagerModel {
    var systemFormat: AVAudioFormat { get async }
    
    var deviceSettings: AudioDeviceSettings { get set }
    var bufferSize: UInt32 { get }
    var inputLatency: UInt32? { get async }
    var engineOutputNode: AVAudioOutputNode? { get }

    var hardware: AudioHardwareManager { get }
    
    var allDevices: [AudioDevice] { get async }
    
    var selectedInputDevice: AudioDevice? { get async }
    var selectedOutputDevice: AudioDevice? { get async }
    var defaultInputDevice: AudioDevice? { get async }
    var defaultOutputDevice: AudioDevice? { get async }

    func updateBufferSize(newValue: UInt32) async
    
    func setInput(device: AudioDevice) async throws
    func setOutput(device: AudioDevice) async throws
    func reconnect() async throws
}
