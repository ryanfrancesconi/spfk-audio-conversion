// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKAudioHardware
import SPFKBase

extension AVAudioInputNode {
    public func update(channelMap: [UInt32]) throws {
        guard let audioUnit else {
            throw NSError(description: "inputNode.audioUnit is nil")
        }

        let channelMapSize = UInt32(MemoryLayout<Int32>.size * channelMap.count)

        // 1 is the 'input' element, 0 is output
        let inputElement: AudioUnitElement = 1

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            inputElement,
            channelMap,
            channelMapSize,
        )

        guard status == noErr else {
            throw NSError(description: "Failed setting kAudioOutputUnitProperty_ChannelMap, error: \(status.fourCC)")
        }
    }
}
