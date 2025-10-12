import Foundation
import SPFKUtils

/// A small engine for playback tests
public class MiniEngine {
    public let workspace = AudioWorkspace()
    
    public var mixer: MixerWrapper? {
        workspace.master?.mixer
    }

    public init() {
    }

    public func start() async throws {
        try await workspace.rebuild()

        try workspace.start()
    }

    public func connect(node: any EngineNode) throws {
        guard let mixer = workspace.master else {
            throw NSError(description: "workspace.master is nil")
        }

        try workspace.engineManager.connectAndAttach(node, to: mixer)
    }
}
