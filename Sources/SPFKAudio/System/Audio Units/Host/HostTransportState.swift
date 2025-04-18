import AudioToolbox
import Foundation

public struct HostTransportState {
    public init() {}

    /**
     @constant    AUHostTransportStateChanged
         True if, since the callback was last called, there was a change to the state of, or
         discontinuities in, the host's transport. Can indicate such state changes as
         start/stop, or seeking to another position in the timeline.
     @constant    AUHostTransportStateMoving
         True if the transport is moving.
     @constant    AUHostTransportStateRecording
         True if the host is recording, or prepared to record. Can be true with or without the
         transport moving.
     @constant    AUHostTransportStateCycling
         True if the host is cycling or looping.
     */
    public var flags = AUHostTransportStateFlags()

    /// Current time of the timeline in samples at the rate of the audio device
    public var currentSamplePosition: Double = 0

    // fractional beat number of loop start
    public var cycleStartBeatPosition: Double = 0

    // fractional beat number of loop end
    public var cycleEndBeatPosition: Double = 0
}
