// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AudioToolbox
import SwiftExtensions

public struct HostAUState {
    public init() {}

    public var isEnabled: Bool = true

    public var musicalContext = HostMusicalContext()
    public var transportState = HostTransportState()

    public var musicalContextBlock: AUHostMusicalContextBlock {
        // Log.debug("musicalContextBlock requested")

        /**  @typedef    AUHostMusicalContextBlock
             @brief        Block by which hosts provide musical tempo, time signature, and beat position.
             @param    currentTempo
                 The current tempo in beats per minute.
             @param    timeSignatureNumerator
                 The numerator of the current time signature.
             @param    timeSignatureDenominator
                 The denominator of the current time signature.
             @param    currentBeatPosition
                 The precise beat position of the beginning of the current buffer being rendered.
             @param    sampleOffsetToNextBeat
                 The number of samples between the beginning of the buffer being rendered and the next beat
                 (can be 0).
             @param    currentMeasureDownbeatPosition
                 The beat position corresponding to the beginning of the current measure.
             @return
                 YES for success.
         */
        func block(currentTempo: UnsafeMutablePointer<Double>?,
                   timeSignatureNumerator: UnsafeMutablePointer<Double>?,
                   timeSignatureDenominator: UnsafeMutablePointer<Int>?,
                   currentBeatPosition: UnsafeMutablePointer<Double>?,
                   sampleOffsetToNextBeat: UnsafeMutablePointer<Int>?,
                   currentMeasureDownbeatPosition: UnsafeMutablePointer<Double>?) -> Bool
        {
            currentTempo?.pointee = musicalContext.currentTempo
            timeSignatureNumerator?.pointee = musicalContext.timeSignatureNumerator
            timeSignatureDenominator?.pointee = musicalContext.timeSignatureDenominator
            currentBeatPosition?.pointee = musicalContext.currentBeatPosition
            sampleOffsetToNextBeat?.pointee = musicalContext.sampleOffsetToNextBeat
            currentMeasureDownbeatPosition?.pointee = musicalContext.currentMeasureDownbeatPosition

            return true
        }
        return block
    }

    public var transportStateBlock: AUHostTransportStateBlock {
        // Log.debug("transportStateBlock requested")

        /**  @typedef    AUHostTransportStateBlock
             @brief        Block by which hosts provide information about their transport state.
             @param    transportStateFlags
                 The current state of the transport.
             @param    currentSamplePosition
                 The current position in the host's timeline, in samples at the audio unit's output sample
                 rate.
             @param    cycleStartBeatPosition
                 If cycling, the starting beat position of the cycle.
             @param    cycleEndBeatPosition
                 If cycling, the ending beat position of the cycle.
             @discussion
                 If the host app provides this block to an AUAudioUnit (as its transportStateBlock), then
                 the block may be called at the beginning of each render cycle to obtain information about
                 the current transport state.

                 Any of the provided parameters may be null to indicate that the audio unit is not interested
                 in that particular piece of information.
         */
        func block(transportStateFlags: UnsafeMutablePointer<AUHostTransportStateFlags>?,
                   currentSamplePosition: UnsafeMutablePointer<Double>?,
                   cycleStartBeatPosition: UnsafeMutablePointer<Double>?,
                   cycleEndBeatPosition: UnsafeMutablePointer<Double>?) -> Bool
        {
            transportStateFlags?.pointee = transportState.flags
            currentSamplePosition?.pointee = transportState.currentSamplePosition
            cycleStartBeatPosition?.pointee = transportState.cycleStartBeatPosition
            cycleEndBeatPosition?.pointee = transportState.cycleEndBeatPosition
            return true
        }
        return block
    }
}
