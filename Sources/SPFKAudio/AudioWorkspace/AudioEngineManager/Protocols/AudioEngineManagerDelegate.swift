import Foundation

public protocol AudioEngineManagerDelegate: AnyObject {
    func audioEngineManager(event: AudioEngineManager.Event) async
    
    func audioEngineManagerAllowInputDevice() async -> Bool // temp name
}
