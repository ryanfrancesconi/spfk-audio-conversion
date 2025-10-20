import Foundation
import SPFKTime

public protocol TransportPlayerDelegate: AnyObject, AudioEngineConnection {
    func transportPlayer(timerEvent event: TransportTimerEvent)
}
