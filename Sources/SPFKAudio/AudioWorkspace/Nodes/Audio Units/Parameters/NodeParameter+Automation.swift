// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import AVFoundation
import SPFKAudioC
import SPFKBase

extension NodeParameter {
    /// the `lastRenderTime` of the avAudioNode or a zero sampleTime AVAudioTime
    private var lastRenderTime: AVAudioTime {
        get async {
            let sampleRate = await sampleRate

            var value = avAudioNode?.lastRenderTime ?? AVAudioTime(sampleTime: 0, atRate: sampleRate)

            if !value.isSampleTimeValid {
                // if we're rendering, take the sample time from the engine
                if let engine = avAudioNode?.engine, engine.isInManualRenderingMode {
                    value = AVAudioTime(sampleTime: engine.manualRenderingSampleTime, atRate: sampleRate)
                } else {
                    // otherwise, a zero sampleTime
                    value = AVAudioTime(sampleTime: 0, atRate: sampleRate)
                }
            }

            return value
        }
    }

    /// Send an automation list to the parameter with an optional offset into the list's timeline.
    ///
    /// The offset in seconds is convenient if you have a set of fixed points but are playing
    /// from somewhere in the middle of them.
    /// - Parameters:
    ///   - events: An array of events
    ///   - offset: A time offset into the events
    public func automate(events: [AutomationEvent], offset: TimeInterval) async throws {
        guard let avAudioNode else {
            throw NSError(description: "Underlying AVAudioNode is nil")
        }

        guard let engine = avAudioNode.engine else {
            throw NSError(description: "\(avAudioNode.debugDescription) engine is nil")
        }

        guard var lastTime = avAudioNode.lastRenderTime else {
            throw NSError(description: "\(avAudioNode.debugDescription) lastRenderTime is nil")
        }

        let sampleRate = await sampleRate

        // In manual rendering, we may not have a valid lastRenderTime, so
        // assume no rendering has yet occurred and start at 0
        if !lastTime.isSampleTimeValid || engine.isInManualRenderingMode {
            lastTime = AVAudioTime(
                sampleTime: 0,
                atRate: sampleRate
            )
        }

        guard lastTime.isSampleTimeValid else {
            throw NSError(description: "\(avAudioNode.debugDescription) isSampleTimeValid is false")
        }

        if offset != 0 {
            lastTime = lastTime.offset(seconds: -offset)
        }

        try await automate(events: events, startTime: lastTime)
    }

    /// Begin automation of the parameter.
    ///
    /// If `startTime` is nil, the automation will be scheduled as soon as possible.
    ///
    /// - Parameter events: automation curve
    /// - Parameter startTime: optional time to start automation
    public func automate(events: [AutomationEvent], startTime: AVAudioTime? = nil) async throws {
        guard let avAudioNode else {
            throw NSError(description: "Underlying AVAudioNode is nil")
        }

        guard let engine = avAudioNode.engine else {
            throw NSError(description: "\(avAudioNode.debugDescription) engine is nil")
        }

        let sampleRate = await sampleRate
        let lastRenderTime = await lastRenderTime

        var startTime = startTime ?? lastRenderTime

        // This is only for realtime automation - not rendering
        if !engine.isInManualRenderingMode,
           startTime.isHostTimeValid && !startTime.isSampleTimeValid {
            // Convert a hostTime based AVAudioTime to sampleTime which is needed for automation to work
            let startTimeSeconds = AVAudioTime.seconds(forHostTime: startTime.hostTime)
            let lastTimeSeconds = AVAudioTime.seconds(forHostTime: lastRenderTime.hostTime)
            let offsetSeconds = startTimeSeconds - lastTimeSeconds

            startTime = lastRenderTime.offset(seconds: offsetSeconds)
        }

        // this must be valid
        guard startTime.isSampleTimeValid else {
            throw NSError(description: "\(avAudioNode.debugDescription) startTime.isSampleTimeValid is false")
        }

        try stopAutomation()

        events.withUnsafeBufferPointer { automationPtr in
            guard let automationBaseAddress = automationPtr.baseAddress else { return }

            guard let observer = ParameterAutomationGetRenderObserver(
                parameter.address,
                avAudioNode.auAudioUnit.scheduleParameterBlock,
                Float(sampleRate),
                Float(startTime.sampleTime),
                automationBaseAddress,
                events.count
            ) else {
                Log.error("Failed to create ParameterAutomationGetRenderObserver for \(avAudioNode.auAudioUnit.audioUnitName ?? "Audio Unit")")
                return
            }

            renderObserverToken = avAudioNode.auAudioUnit.token(byAddingRenderObserver: observer)
        }
    }

    /// Stop automation
    public func stopAutomation() throws {
        guard let avAudioNode else {
            throw NSError(description: "Underlying AVAudioNode is nil")
        }

        if let token = renderObserverToken {
            avAudioNode.auAudioUnit.removeRenderObserver(token)
        }
    }

    /// Ramp from a source value
    ///
    /// - Parameters:
    ///   - start: initial value
    ///   - target: destination value
    ///   - duration: duration to ramp to the target value in seconds
    public func ramp(from start: AUValue, to target: AUValue, duration: Float) async {
        let sampleRate = await self.sampleRate

        ramp(to: start, duration: 0.02, delay: 0, sampleRate: sampleRate.float)
        ramp(to: target, duration: duration, delay: 0.02, sampleRate: sampleRate.float)
    }
}
