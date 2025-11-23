import AVFoundation
import Foundation
import SPFKBase

public protocol AudioEngineManagerModel: AnyObject,
    AudioEngineConnection,
    EngineRendererModel,
    CustomStringConvertible,
    CustomDebugStringConvertible {
    // MARK: - Properties

    var systemFormat: AVAudioFormat? { get }
    var engine: AVAudioEngine { get }
    var allowInput: Bool { get async }
    var inputNode: AVAudioInputNode? { get async }
    var outputNode: AVAudioOutputNode { get }

    // MARK: - Engine State

    func startEngine() throws
    func stopEngine()
    func resetEngine()
    func rebuildEngine() async
}
