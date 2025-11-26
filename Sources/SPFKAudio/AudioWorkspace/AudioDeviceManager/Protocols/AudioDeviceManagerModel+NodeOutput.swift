import AVFoundation
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManagerModel {
    public func updatePreferredOutputChannels() async throws {
        guard let selectedOutputDevice = await selectedOutputDevice else {
            throw NSError(description: "selectedOutputDevice is nil")
        }

        guard let engineDevice = await engineDevice else {
            throw NSError(description: "engineDevice is nil")
        }

        let allowInput = await self.allowInput

        // If we're allowing input that means that we're using the engine's aggregate.
        // So, we must look at its preferredChannelsForStereo and set that on the channel map
        let currentDevice = allowInput ? engineDevice : selectedOutputDevice

        guard let stereoPair = currentDevice.preferredChannelsForStereo(scope: .output) else {
            throw NSError(description: "Failed to get preferredChannelsForStereo for \(selectedOutputDevice.name)")
        }

        Log.debug(selectedOutputDevice.name, "returned", stereoPair)

        try updateOutputChannelMap(
            stereoPair: stereoPair
        )
    }

    /**
     Example Apple gave here:
     https://developer.apple.com/forums/thread/16790

     ```
     AURemoteIO Client Format 2 Channels:   0, 1
                                            |  |_______
                                            |_______   |
                                                    |  |
     Output Audio Unit Channel Map      :   -1, -1, 0, 1
                                                    |  |
     AURemoteIO Output Format 4 Channels:   0,  1,  2, 3
                                            L  R  HDMI1 HDMI2
     ```
     */
    public func updateOutputChannelMap(stereoPair: StereoPair) throws {
        guard let engineOutputNode else {
            throw NSError(description: "engineOutputNode is nil")
        }

        guard let audioUnit = engineOutputNode.audioUnit else {
            throw NSError(description: "Failed to get audioUnit reference from engineOutputNode")
        }

        let channelCount = engineOutputNode.outputFormat(forBus: 0).channelCount

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
            channelMapSize
        )

        guard status == noErr else {
            throw NSError(description: "Failed setting kAudioOutputUnitProperty_ChannelMap, error: \(status.fourCC)")
        }

        Log.debug("set to", stereoPair, "channelMap", channelMap, "total channels", channelCount)
    }
}

extension AudioDeviceManagerModel {
    private var currentNodeOutputDevice: AudioDevice? {
        get async {
            guard let audioUnit = engineOutputNode?.audioUnit else {
                Log.error("Failed to get audioUnit reference from engine.outputNode")
                return nil
            }

            var id: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)

            let err = AudioUnitGetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                &size
            )

            guard err == noErr else {
                Log.error("Failed to get engine output node device ID, error: \(err)")
                return nil
            }

            return await AudioObjectPool.shared.lookup(id: id)
        }
    }

    /// NOTE: this method of direct setting of the device with no input
    /// doesn't work with airpods -
    /// potentially other blue tooth headsets as well.
    func setEngineNodeOutput(to device: AudioDevice) async throws {
        if let currentNodeOutputDevice = await currentNodeOutputDevice,
           currentNodeOutputDevice == device
        {
            Log.debug(device, "is already set as the engine's output")
            return
        }

        guard let audioUnit = engineOutputNode?.audioUnit else {
            throw NSError(description: "Failed to get audioUnit reference from engine.outputNode")
        }

        var id = device.id
        let name = device.name

        Log.debug("Attempting to set engine output to", name)

        let outputElement: AudioUnitElement = 0

        let err = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            outputElement,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard err == noErr else {
            throw NSError(description: "Unable to set output audio unit to device \(name), error: \(err.fourCC)")
        }

        Log.debug("Engine output set to", name)

        try await updatePreferredOutputChannels()
    }

    func reconnectNodeOutput() async throws {
        guard await !allowInput else {
            Log.error("Input is enabled, using system settings not node output. Ignoring this call.")
            return
        }

        let selectedEngineOutputDevice = await selectedEngineOutputDevice
        let currentNodeOutputDevice = await currentNodeOutputDevice

        guard let selectedEngineOutputDevice else {
            Log.debug("selectedEngineOutputDevice is nil")
            return
        }

        guard selectedEngineOutputDevice != currentNodeOutputDevice else {
            Log.debug(currentNodeOutputDevice, "Device is still connected, no need to change")
            return
        }

        // note this will create an engine configuration change event
        try await setEngineNodeOutput(to: selectedEngineOutputDevice)
    }
}
