import AVFoundation
import SPFKUtils

extension AVAudioMixerNode {
    public var inputBussesCount: Int {
        auAudioUnit.inputBusses.count
    }

    public var inputs: [AVAudioConnectionPoint] {
        guard let engine else { return [] }

        var out = [AVAudioConnectionPoint]()

        for i in 0 ..< numberOfInputs {
            if let input = engine.inputConnectionPoint(for: self, inputBus: i) {
                out.append(input)
            }
        }

        return out
    }

    public var outputs: [AVAudioConnectionPoint] {
        guard let engine else { return [] }

        return engine.outputConnectionPoints(for: self, outputBus: 0)
    }

    /// Resize underlying AVAudioMixerNode input busses array to accomodate for required count of inputs.
    ///
    /// ```
    /// let desiredInputCount = 5
    /// let allowedCount = mixer.resizeInputBussesArray(requiredSize: desiredInputCount)
    ///// allowedCount is now 5 or less
    /// ```
    /// If engine has already started, underlying AVAudioMixerNode won't resize its input busses
    /// array when new input nodes are added into it, which may eventually cause a crash.
    ///
    /// Use this function to avoid that and resize input busses array manually before adding new inputs to the mixer.
    ///
    /// If the current busses array size is less than required, it will attempt to resize the array.
    /// Otherwise, no changes will be made.
    ///
    /// If engine has not yet started, you shouldn't need to use this function.
    /// - Parameter requiredSize: how many input busses you need in the mixer
    /// - Returns: new input busses array size or its current size in case it's less than required
    ///  and resize failed, or can't be done.
    public func resizeInputBussesArray(requiredSize: Int) -> Int {
        let busses = auAudioUnit.inputBusses

        guard busses.isCountChangeable else {
            // input busses array is not changeable
            return min(busses.count, requiredSize)
        }

        if busses.count < requiredSize {
            do {
                try busses.setBusCount(requiredSize)
                return requiredSize
            } catch {
                Log.error(error)

                // could not resize input busses array to required size
                return busses.count
            }
        }
        // current input busses array already matches or exceeds required size
        return requiredSize
    }

    /// Make a connection without breaking other connections.
    public func connectMixer(input: AVAudioNode, format: AVAudioFormat? = nil) {
        guard let engine else {
            // Log.error("Engine is nil")
            return
        }

        let format = format ?? engine.outputFormat

        var points = engine.outputConnectionPoints(for: input, outputBus: 0)

        if points.contains(where: { $0.node === self }) { return }

        points.append(AVAudioConnectionPoint(node: self, bus: nextAvailableInputBus))

        engine.connect(input, to: points, fromBus: 0, format: format)
    }
}
