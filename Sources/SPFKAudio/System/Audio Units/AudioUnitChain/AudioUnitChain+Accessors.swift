import AVFoundation
import Foundation

extension AudioUnitChain {
    func totalLatency() async -> TimeInterval {
        await data.totalLatency
    }
}

extension AudioUnitChain: EngineAccess {
    public var engineManager: AudioEngineManagerModel? { delegate?.engineManager }
}
