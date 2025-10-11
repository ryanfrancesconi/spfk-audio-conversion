import AVFoundation
import Foundation
import SPFKUtils

public protocol AudioEngineManagerModel: AnyObject,
    AudioEngineConnection,
    EngineRendererModel,
    CustomStringConvertible,
    CustomDebugStringConvertible {
    // -
    var systemFormat: AVAudioFormat? { get }
    var engine: AVAudioEngine { get }
    var allowInput: Bool { get }
    var inputNode: AVAudioInputNode? { get }
    var outputNode: AVAudioOutputNode { get }

    func startEngine() throws
    func stopEngine()
    func resetEngine()
    func rebuildEngine()
}
