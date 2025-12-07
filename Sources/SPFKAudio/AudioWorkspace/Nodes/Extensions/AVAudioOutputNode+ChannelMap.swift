// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioHardware
import SPFKBase

extension AVAudioOutputNode {
    public func update(preferredOutputs stereoPair: StereoPair) throws {
        guard let audioUnit else {
            throw NSError(description: "Failed to get audioUnit reference from engineOutputNode")
        }

        let channelCount = outputFormat(forBus: 0).channelCount

        // sanity check
        guard channelCount > 1, channelCount <= 1024 else {
            throw NSError(description: "Error: invalid number of output channels (\(channelCount)")
        }

        var channelMap = [Int32](repeating: -1, count: Int(channelCount))

        // stereoPair starts at 1, so zero indexed array
        let leftIndex = Int(stereoPair.left) - 1
        let rightIndex = Int(stereoPair.right) - 1

        guard channelMap.indices.contains(leftIndex),
              channelMap.indices.contains(rightIndex)
        else {
            throw NSError(description: "Invalid indices are passed in: \(leftIndex)-\(rightIndex)")
        }

        channelMap[leftIndex] = 0
        channelMap[rightIndex] = 1

        let channelMapSize = UInt32(MemoryLayout<Int32>.size * channelMap.count)

        // 1 is the 'input' element, 0 is output
        let outputElement: AudioUnitElement = 0

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Global,
            outputElement,
            &channelMap,
            channelMapSize,
        )

        guard status == noErr else {
            throw NSError(description: "Failed setting kAudioOutputUnitProperty_ChannelMap, error: \(status.fourCC)")
        }
    }
}
