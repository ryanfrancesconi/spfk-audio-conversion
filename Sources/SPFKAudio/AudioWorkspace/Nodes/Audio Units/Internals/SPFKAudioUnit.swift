// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AudioToolbox
import AVFoundation
import SPFKAudioBase
import SPFKAudioC
import SPFKBase

/// Interally defined AudioUnit which instantiates a DSP kernel based on the componentSubType.
open class SPFKAudioUnit: AUAudioUnit {
    private var inputBusArray: [AUAudioUnitBus] = []
    private var outputBusArray: [AUAudioUnitBus] = []
    private var internalBuffers: [AVAudioPCMBuffer] = []

    // Default supported channel capabilities
    public var supportedLeftChannelCount: NSNumber = 2
    public var supportedRightChannelCount: NSNumber = 2

    // MARK: AUAudioUnit Overrides

    override public var channelCapabilities: [NSNumber]? {
        return [supportedLeftChannelCount, supportedRightChannelCount]
    }

    /// Allocate the render resources
    override public func allocateRenderResources() throws {
        try super.allocateRenderResources()

        if let inputFormat = inputBusArray.first?.format {
            update(inputFormat: inputFormat)
        }

        if let outputFormat = outputBusArray.first?.format {
            allocateRenderResourcesDSP(dsp, outputFormat.channelCount, outputFormat.sampleRate)
        }
    }

    private func update(inputFormat: AVAudioFormat) {
        // we don't need to allocate a buffer if we can process in place
        guard !canProcessInPlace || inputBusArray.count > 1 else { return }

        for i in inputBusArray.indices {
            if let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: maximumFramesToRender) {
                setBufferDSP(dsp, buffer.mutableAudioBufferList, i)
                internalBuffers.append(buffer)
            }
        }
    }

    /// Delllocate Render Resources
    override public func deallocateRenderResources() {
        super.deallocateRenderResources()
        deallocateRenderResourcesDSP(dsp)
        internalBuffers = []
    }

    /// Reset the DSP
    override public func reset() {
        resetDSP(dsp)
    }

    private lazy var _inputBusses: AUAudioUnitBusArray = .init(audioUnit: self, busType: .input, busses: inputBusArray)
    private lazy var _outputBusses: AUAudioUnitBusArray = .init(audioUnit: self, busType: .output, busses: outputBusArray)

    override public var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override public var outputBusses: AUAudioUnitBusArray { _outputBusses }

    /// Internal render block
    override public var internalRenderBlock: AUInternalRenderBlock {
        internalRenderBlockDSP(dsp)
    }

    private var _parameterTree: AUParameterTree?

    /// Parameter tree
    override public var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set {
            _parameterTree = newValue

            _parameterTree?.implementorValueObserver = { [unowned self] parameter, value in
                setParameterValueDSP(self.dsp, parameter.address, value)
            }

            _parameterTree?.implementorValueProvider = { [unowned self] parameter in
                getParameterValueDSP(self.dsp, parameter.address)
            }

            _parameterTree?.implementorStringFromValueCallback = { _, valuePtr in
                guard let valuePtr else { return "Invalid " }

                return String(format: "%.2f", valuePtr.pointee)
            }
        }
    }

    /// Whether the unit can process in place
    override public var canProcessInPlace: Bool {
        canProcessInPlaceDSP(dsp)
    }

    /// Set in order to bypass processing
    override public var shouldBypassEffect: Bool {
        get { getBypassDSP(dsp) }
        set { setBypassDSP(dsp, newValue) }
    }

    // MARK: Lifecycle

    /// DSP Reference
    public private(set) var dsp: DSPRef

    /// Initialize with component description and options
    /// - Parameters:
    ///   - componentDescription: Audio Component Description
    ///   - options: Audio Component Instantiation Options
    /// - Throws: error
    override public init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        // Create pointer to C++ DSP code.
        guard let dsp = createDSP(componentDescription.componentSubType) else {
            throw NSError(description: "Failed to create DSP for \(componentDescription)")
        }

        self.dsp = dsp

        try super.init(componentDescription: componentDescription, options: options)

        parameterTree = AUParameterTree.createTree(withChildren: [])

        try createBusses(format: nil)
    }

    /// create audio bus connection points
    private func createBusses(format: AVAudioFormat?) throws {
        let format = format ?? AudioDefaults.shared.unsafeSystemFormat

        // Log.debug(format)

        inputBusArray.removeAll()
        outputBusArray.removeAll()

        for _ in 0 ..< inputBusCountDSP(dsp) {
            try inputBusArray.append(
                AUAudioUnitBus(format: format)
            )
        }

        // All  nodes have one output bus.
        try outputBusArray.append(
            AUAudioUnitBus(format: format)
        )
    }

    public func update(format: AVAudioFormat) throws {
        try createBusses(format: format)

        _inputBusses = .init(audioUnit: self, busType: .input, busses: inputBusArray)
        _outputBusses = .init(audioUnit: self, busType: .output, busses: outputBusArray)
    }

    deinit {
        deleteDSP(dsp)
    }

    /// Create an array of values to use as waveforms or other things inside an audio unit
    /// - Parameters:
    ///   - wavetable: Array of float values
    ///   - index: Optional index at which to set the table (useful for multiple waveform audio units)
    public func setWavetable(_ wavetable: [AUValue], index: Int = 0) {
        setWavetableDSP(dsp, wavetable, wavetable.count, Int32(index))
    }

    /// Set wave table
    /// - Parameters:
    ///   - data: A pointer to the data
    ///   - size: Size of the table
    ///   - index: Index at which to set the value
    public func setWavetable(data: UnsafePointer<AUValue>?, size: Int, index: Int = 0) {
        setWavetableDSP(dsp, data, size, Int32(index))
    }
}
