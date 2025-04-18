import AVFoundation
import Foundation
import SimplyCoreAudio

public protocol DeviceAccess: AnyObject {
    var deviceManager: (any AudioDeviceManagerModel)? { get }
}

/// Device options available for public access
public protocol AudioDeviceManagerModel {
    var systemFormat: AVAudioFormat { get set }
    var engineOutputNode: AVAudioOutputNode? { get }
    var deviceSettings: DeviceSettings { get set }
    var bufferSize: UInt32 { get set }
    var inputLatency: UInt32? { get }
    var outputLatency: UInt32? { get }
    var allDevices: [AudioDevice] { get }
    var selectedInputDevice: AudioDevice? { get }
    var selectedOutputDevice: AudioDevice? { get }
    var defaultInputDevice: AudioDevice? { get }
    var defaultOutputDevice: AudioDevice? { get }

    func setInput(device: AudioDevice)
    func setOutput(device: AudioDevice) throws
}
