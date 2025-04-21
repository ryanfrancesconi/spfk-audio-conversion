import AVFoundation
import SimplyCoreAudio
import SPFKUtils

// In general, no longer keeping different device preferences from the system audio due
// to incompatibilities with AVAudioEngine and its inputNode inflexibility.
// The exception is: if input is disabled, still use
// the engine audioUnit output directly to the output device selection.
// NOTE: this method of direct setting of the device with no input doesn't work with airpods -
// potentially other blue tooth headsets as well.

public class AudioDeviceManager: AudioDeviceManagerModel {
    public enum Event {
        case sampleRateChanged(Double)
        case inputDeviceChanged(device: AudioDevice)
        case outputDeviceChanged(device: AudioDevice)
        case deviceListChanged(addedDevices: [AudioDevice], removedDevices: [AudioDevice])
        case deviceProcessorOverload
    }

    public var eventHandler: ((Event) -> Void)?

    func send(event: Event) {
        Task { @MainActor in
            eventHandler?(event)
        }
    }

    var hardwareObservers: [NSObjectProtocol] = []
    var inputDeviceObserver: NSObjectProtocol?
    var outputDeviceObserver: NSObjectProtocol?

    public let hardware = SimplyCoreAudio()

    // MARK: - Latency

    // Cache this value for the selected device
    internal var _inputLatency: UInt32?
    public var inputLatency: UInt32? {
        if let _inputLatency { return _inputLatency }
        _inputLatency = inputDeviceLatency
        return _inputLatency
    }

    // Cache this value for the selected device
    internal var _outputLatency: UInt32?
    public var outputLatency: UInt32? {
        if let _outputLatency { return _outputLatency }
        _outputLatency = inputDeviceLatency
        return _outputLatency
    }

    private var _bufferSize: UInt32 = 256
    public var bufferSize: UInt32 {
        get { _bufferSize }

        set {
            guard newValue != _bufferSize else { return }

            // the engine doesn't like this if input is disabled...
            guard deviceSettings.allowInput && allowInput else {
                Log.error("AVAudioEngine doesn't like the hardware buffer size changed when there is no input.")
                return
            }

            _bufferSize = newValue
            updateBufferSize()
        }
    }

    // TODO: once this model protocol is adopted, won't need this static struct and can keep a class variable here
    public var systemFormat: AVAudioFormat {
        get {
            AudioDefaults.systemFormat
        }

        set {
            AudioDefaults.systemFormat = newValue

            do {
                try setNominalSampleRate(to: newValue.sampleRate)
            } catch {
                Log.error(error)
            }
        }
    }

    // MARK: - Device convenience

    public var allDevices: [AudioDevice] { hardware.allDevices }

    public var bluetoothDevices: [AudioDevice] {
        allDevices.filter {
            $0.transportType == .bluetooth
        }
    }

    public var aggregateDevices: [AudioDevice] {
        allDevices.filter {
            $0.transportType == .aggregate
        }
    }

    public var selectedInputDevice: AudioDevice? {
        guard deviceSettings.allowInput else { return nil }
        return hardware.defaultInputDevice
    }

    public var selectedOutputDevice: AudioDevice? {
        allowInput ? hardware.defaultOutputDevice :
            selectedEngineOutputDevice
    }

    public var defaultInputDevice: AudioDevice? { hardware.defaultInputDevice }
    public var defaultOutputDevice: AudioDevice? { hardware.defaultOutputDevice }

    public var deviceSettings = DeviceSettings()

    /// return the current engine in this block so that the `AudioDeviceManager` can set a device on it's output audio unit
    internal var engineRef: (() -> AVAudioEngine?)?

    public var engineOutputNode: AVAudioOutputNode? { engineRef?()?.outputNode }

    public init(settings: DeviceSettings = DeviceSettings()) {
        // default to the system selected devices if nothing is passed in
        deviceSettings = DeviceSettings(
            inputUID: settings.inputUID ?? defaultInputDevice?.uid,
            outputUID: settings.outputUID ?? defaultOutputDevice?.uid
        )

        addHardwareObservers()
    }

    deinit {
        removeHardwareObservers()
    }

    private func updateBufferSize() {
        if hasInputDevice, let device = selectedInputDevice {
            if !device.setBufferFrameSize(bufferSize, scope: .input) {
                Log.error("Unable to set input buffer frame size for", device.name)
            }
            if !device.setBufferFrameSize(bufferSize, scope: .output) {
                Log.error("Unable to set output buffer frame size for", device.name)
            }

            Log.debug("🎤 Input Latency", device.latency(scope: .input), inputLatencyInSeconds)
        }

        if let device = selectedOutputDevice {
            if !device.setBufferFrameSize(bufferSize, scope: .input) {
                Log.error("Unable to set input buffer frame size for", device.name)
            }
            if !device.setBufferFrameSize(bufferSize, scope: .output) {
                Log.error("Unable to set output buffer frame size for", device.name)
            }

            Log.debug("🎤 Output Latency", device.latency(scope: .output))
        }

        Log.debug("🔈 Updated I/O Buffer Size to", bufferSize)
    }

    // MARK: - Device Setters

    public func setInput(device: AudioDevice) {
        guard device != selectedInputDevice else { return }

        defer {
            try? setInputSampleRate(to: systemSampleRate)
        }

        deviceSettings.inputUID = device.uid

        // will set device
        device.isDefaultInputDevice = true
        addInputDeviceObserver(for: device)

        _inputLatency = nil // uncache this
    }

    public func setOutput(device: AudioDevice) throws {
        guard device != selectedOutputDevice else { return }

        defer {
            try? setOutputSampleRate(to: systemSampleRate)
        }

        deviceSettings.outputUID = device.uid

        guard deviceSettings.allowInput else {
            try setNodeOutput(to: device)
            // will call updatePreferredOutputChannels
            return
        }

        // will set device
        device.isDefaultOutputDevice = true

        try updatePreferredOutputChannels()
        addOutputDeviceObserver(for: device)
    }
}
