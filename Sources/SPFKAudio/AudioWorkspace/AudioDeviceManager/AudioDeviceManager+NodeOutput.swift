// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioHardware
import SPFKBase

extension AudioDeviceManager {
    public func updatePreferredOutputChannels() async throws {
        guard let selectedOutputDevice = await selectedOutputDevice else {
            throw NSError(description: "selectedOutputDevice is nil")
        }

        guard let engineDevice = try await engineDevice() else {
            throw NSError(description: "engineDevice is nil, no need to set channel map")
        }

        let allowInput = await allowInput

        // If we're allowing input that means that we're using the AVAudioEngine's aggregate.
        // So, we must look at its preferredChannelsForStereo and set that on the channel map
        let currentDevice = allowInput ? engineDevice : selectedOutputDevice

        guard let stereoPair = currentDevice.preferredChannelsForStereo(scope: .output) else {
            throw NSError(description: "Failed to get preferredChannelsForStereo for \(selectedOutputDevice.name)")
        }

        Log.debug(selectedOutputDevice.name, "returned", stereoPair)

        try updateOutputChannelMap(stereoPair: stereoPair)
    }

    /// Example Apple gave here:
    /// https://developer.apple.com/forums/thread/16790
    ///
    /// - Parameter stereoPair: The channels to set on the output node
    ///
    /// ```
    /// AURemoteIO Client Format 2 Channels:   0, 1
    ///                                        |  |_______
    ///                                        |_______   |
    ///                                                |  |
    /// Output Audio Unit Channel Map      :   -1, -1, 0, 1
    ///                                                |  |
    /// AURemoteIO Output Format 4 Channels:   0,  1,  2, 3
    ///                                        L   R   HDMI1  HDMI2
    /// ```
    private func updateOutputChannelMap(stereoPair: StereoPair) throws {
        guard let outputNode = engineOutputNode else {
            throw NSError(description: "Failed to get engineOutputNode")
        }

        try outputNode.update(preferredOutputs: stereoPair)

        Log.debug("set to", stereoPair)
    }
}

extension AudioDeviceManager {
    private func currentNodeOutputDevice() async throws -> AudioDevice? {
        guard let audioUnit = engineOutputNode?.audioUnit else {
            Log.error("Failed to get audioUnit reference from engine.outputNode")
            return nil
        }

        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            &size,
        )

        guard noErr == status else {
            Log.error("Failed to get engine output node device ID, error: \(status.fourCC)")
            return nil
        }

        return try await AudioObjectPool.shared.lookup(id: id)
    }

    func reconnectNodeOutput() async throws {
        guard await !allowInput else {
            Log.error("Input is enabled, using system settings not node output. Ignoring this call.")
            return
        }

        let deviceSettingsOutputDevice = try await deviceSettingsOutputDevice()
        let currentNodeOutputDevice = try await currentNodeOutputDevice()

        guard let deviceSettingsOutputDevice else {
            Log.debug("selectedEngineOutputDevice is nil")
            return
        }

        guard deviceSettingsOutputDevice != currentNodeOutputDevice else {
            Log.debug(currentNodeOutputDevice, "Device is still connected, no need to change")
            return
        }

        // note this will create an engine configuration change event
        try await setEngineNodeOutput(to: deviceSettingsOutputDevice)
    }

    /// NOTE: this method of direct setting of the device with no input
    /// doesn't work with airpods -
    /// potentially other blue tooth headsets as well.
    func setEngineNodeOutput(to device: AudioDevice) async throws {
        if let currentNodeOutputDevice = try await currentNodeOutputDevice(),
           currentNodeOutputDevice == device
        {
            Log.debug(device, "is already set as the engine's output")
            return
        }

        guard let engineOutputNode else {
            throw NSError(description: "engineOutputNode is nil")
        }

        guard let audioUnit = engineOutputNode.audioUnit else {
            throw NSError(description: "Failed to get audioUnit reference from engine.outputNode")
        }

        var id = device.id
        let name = device.name

        Log.debug("Attempting to set engine output to", name)

        let outputElement: AudioUnitElement = 0

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            outputElement,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size),
        )

        guard noErr == status else {
            throw NSError(description: "Unable to set output audio unit to device \(name), error: \(status.fourCC)")
        }

        Log.debug("Engine output set to", name)

        try await updatePreferredOutputChannels()
    }
}
