import Foundation

public protocol AudioDeviceManagerDelegate: AnyObject, AudioEngineAccess {
    func audioDeviceManager(event: AudioDeviceManager.Event)
}
