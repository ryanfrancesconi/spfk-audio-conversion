//  Copyright © 2020 Audio Design Desk. All rights reserved.

import Accelerate
import AVFoundation
import OTCore
import SPFKUtils

/// Tap to do amplitude analysis on any node. Limited to 2 channels.
/// start() will add the tap, and stop() will remove it.
public class AmplitudeTap {
    /// Determines if the returned amplitude value is the rms or peak value
    public var analysisMode: AnalysisMode = .peak

    // @OTAtomicsThreadSafe
    private var amp: [Float] = Array(repeating: 0, count: 2)

    public private(set) var bufferSize: UInt32

    /// Tells whether the node is processing (ie. started, playing, or active)
    // @OTAtomicsThreadSafe
    public private(set) var isStarted: Bool = false

    /// The bus to install the tap onto
    public var bus: Int = 0 {
        didSet {
            if isStarted {
                stop()
                start()
            }
        }
    }

    private var _input: AVAudioNode?
    public var input: AVAudioNode? {
        get { _input }
        set {
            guard newValue != _input else { return }
            let wasStarted = isStarted

            // if the input changes while it's on, stop and start the tap
            if wasStarted {
                stop()
            }

            _input = newValue

            // if the input changes while it's on, stop and start the tap
            if wasStarted {
                start()
            }
        }
    }

    public var amplitude: Float {
        amp.reduce(0, +) / 2
    }

    public var leftAmplitude: Float {
        amp[0]
    }

    public var rightAmplitude: Float {
        amp[1]
    }

    public var taper: AUValue = FadeDescription.AudioTaper.taper.in

    private var eventHandler: (([Float]) -> Void)?

    /// - parameter input: Node to analyze
    public init(_ input: AVAudioNode?,
                bufferSize: UInt32 = 1024,
                eventHandler: (([Float]) -> Void)?) {
        self.bufferSize = bufferSize
        self.input = input
        self.eventHandler = eventHandler
    }

    /// Enable the tap on input
    public func start() {
        guard let input, !isStarted else {
            return
        }

        isStarted = true

        // a node can only have one tap at a time installed on it
        // make sure any previous tap is removed.
        // We're making the assumption that the previous tap (if any)
        // was installed on the same bus as our bus.
        removeTap()

        // just double check this here as it is required to be valid
        guard input.engine != nil else {
            Log.error("The tapped node's engine is nil")
            return
        }

        input.installTap(
            onBus: bus,
            bufferSize: bufferSize,
            format: nil,
            block: { [weak self] in
                self?.process(buffer: $0, at: $1)
            }
        )
    }

    /// Remove the tap on the input
    public func stop() {
        removeTap()
        isStarted = false
        amp[0] = 0
        amp[1] = 0
        eventHandler?(amp)
    }

    // AVAudioNodeTapBlock
    private func process(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let floatData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        let length = vDSP_Length(buffer.frameLength)

        // Log.debug("actual buffer size:", length, "actual sample rate", buffer.format.sampleRate)

        // n is the channel
        for n in 0 ..< channelCount {
            let data = floatData[n]
            var value: Float = 0

            if analysisMode == .peak {
                var index: vDSP_Length = 0
                vDSP_maxvi(data, 1, &value, &index, length)

            } else {
                vDSP_rmsqv(data, 1, &value, length)
            }

            amp[n] = value.normalized(from: 0 ... 1, taper: taper)
        }

        eventHandler?(amp)
    }

    private func removeTap() {
        guard let input, input.engine != nil else {
            Log.error("\(input?.description ?? "input is nil") engine is nil")
            return
        }

        input.removeTap(onBus: bus)
    }

    /// remove the tap and nil out the input reference
    /// this is important in regard to retain cycles on your input node
    public func dispose() {
        if isStarted {
            stop()
        }

        input = nil
        eventHandler = nil
    }
}
