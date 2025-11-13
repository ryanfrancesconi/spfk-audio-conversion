import Foundation

public protocol AudioEngineManagerDelegate: AnyObject {
    func audioEngineManager(event: AudioEngineManager.Event)
    
    // audioEngineManager( getDeviceProperty
    
    func audioEngineManagerAllowInputDevice() -> Bool // temp name
}
