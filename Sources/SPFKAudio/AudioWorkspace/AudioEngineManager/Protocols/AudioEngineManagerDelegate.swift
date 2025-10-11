import Foundation

public protocol AudioEngineManagerDelegate: AnyObject, AudioDeviceAccess {
    func audioEngineManager(event: AudioEngineManager.Event)
}
