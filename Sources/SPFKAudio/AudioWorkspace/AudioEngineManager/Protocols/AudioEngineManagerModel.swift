import AVFoundation
import Foundation
import SPFKUtils

public protocol AudioEngineManagerModel: AnyObject,
    AudioEngineConnection,
    EngineRendererModel,
    CustomStringConvertible,
    CustomDebugStringConvertible {
    // MARK: - Properties

    var systemFormat: AVAudioFormat? { get }
    var engine: AVAudioEngine { get }
    var allowInput: Bool { get }
    var inputNode: AVAudioInputNode? { get }
    var outputNode: AVAudioOutputNode { get }

    // MARK: - Engine State

    func startEngine() throws
    func stopEngine()
    func resetEngine()
    func rebuildEngine()
}
