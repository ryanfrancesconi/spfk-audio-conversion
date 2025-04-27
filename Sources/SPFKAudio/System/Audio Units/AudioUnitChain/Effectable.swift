import Foundation

public protocol Effectable: AnyObject {
    var audioUnitChain: AudioUnitChain { get }
}
