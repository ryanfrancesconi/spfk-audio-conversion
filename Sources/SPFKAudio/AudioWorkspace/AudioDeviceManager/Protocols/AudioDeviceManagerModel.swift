import AVFoundation
import Foundation
import SimplyCoreAudio

/// Primary audio device access
public protocol AudioDeviceManagerModel {
    var systemFormat: AVAudioFormat { get set }
    var deviceSettings: AudioDeviceSettings { get set }
    var bufferSize: UInt32 { get set }
    var inputLatency: UInt32? { get }

    var engineOutputNode: AVAudioOutputNode? { get }

    var allDevices: [AudioDevice] { get }
    var selectedInputDevice: AudioDevice? { get }
    var selectedOutputDevice: AudioDevice? { get }
    var defaultInputDevice: AudioDevice? { get }
    var defaultOutputDevice: AudioDevice? { get }

    func setInput(device: AudioDevice)
    func setOutput(device: AudioDevice) throws
    func reconnect() throws
}
