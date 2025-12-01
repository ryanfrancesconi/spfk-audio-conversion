import Foundation

public protocol AudioEngineManagerDelegate: Sendable {
    func audioEngineManager(event: AudioEngineManager.Event) async
    func audioEngineManagerAllowInputDevice() async -> Bool // temp name
}
