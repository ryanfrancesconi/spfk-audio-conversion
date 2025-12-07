import Foundation
import SPFKAUHost
import SPFKTime

@MainActor
public protocol TransportPlayerDelegate: AnyObject, AudioEngineConnection {
    func transportPlayer(timerEvent event: TransportTimerEvent)
    func transportPlayer(amplitudeEvent event: [Float])
    func transportPlayer(shouldRestartAtTime time: TimeInterval)
}
