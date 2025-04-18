import SPFKUtils
import AVFoundation
import Foundation

public protocol EngineAccess: AnyObject {
    var engineManager: (any AudioEngineManagerModel)? { get }
}

/// Engine options available for public access
public protocol AudioEngineManagerModel: AnyObject, EngineRendererModel, CustomStringConvertible, CustomDebugStringConvertible {
    var systemFormat: AVAudioFormat { get set }
    var engine: AVAudioEngine { get }
    var allowInput: Bool { get }
    var inputNode: AVAudioInputNode? { get }
    var outputNode: AVAudioOutputNode { get }
    
    func startEngine() throws
    func stopEngine()
    func resetEngine()
    func rebuildEngine()
    func connectAndAttach(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) throws
}

public protocol EngineRendererModel {
    var renderIsCanceled: Bool { get }

    func render(
        to audioFile: AVAudioFile,
        duration: Double,
        renderUntilSilent: Bool,
        prerender: (() -> Void)?,
        postrender: (() -> Void)?,
        progress progressHandler: ((ProgressValue1) -> Void)?
    ) throws

    func cancelRender()
}
