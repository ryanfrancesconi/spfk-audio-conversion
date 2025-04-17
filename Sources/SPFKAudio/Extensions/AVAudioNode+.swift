//  Copyright © 2021 Audio Design Desk. All rights reserved.

import SPFKUtils
import SPFKUtilsC
import AVFoundation

extension AVAudioNode {
    public var ioConnectionDescription: String {
        let name = auAudioUnit.audioUnitName ?? className

        guard let engine else {
            return "\(name) <engine is nil> → 🔇"
        }

        let inputPoint = engine.inputConnectionPoint(for: self, inputBus: 0)
        let outputPoints = engine.outputConnectionPoints(for: self, outputBus: 0)

        let icon = outputPoints.count > 0 ? "→" : "🔇"
        let inputConnected = inputPoint != nil ? "✓ Input" : "No Input"
        var out = name + " (\(inputConnected), \(outputPoints.count) out\(outputPoints.pluralString)) \(icon) "

        for point in outputPoints {
            if let node = point.node {
                if node == engine.outputNode {
                    out += "🔊" // made it to the engine output
                    break
                } else {
                    out += node.ioConnectionDescription
                }
            }
        }

        return out
    }

    public var isOutputNodeConnected: Bool {
        guard let engine else { return false }
        let points = engine.outputConnectionPoints(for: self, outputBus: 0)
        return points.isNotEmpty
    }
}

extension AVAudioNode {
    /// Convenience to disconnect via the engine if it's non nil
    public func disconnectOutput() {
        ExceptionCatcherOperation({ [weak self] in
            guard let self else { return }

            engine?.disconnectNodeOutput(self)

        }, { exception in
            Log.error(exception)
        })
    }

    /// Convenience to disconnect via the engine if it's non nil
    public func disconnectInput() {
        ExceptionCatcherOperation({ [weak self] in
            guard let self else { return }

            engine?.disconnectNodeInput(self)

        }, { exception in
            Log.error(exception)
        })
    }

    public func detach() {
        ExceptionCatcherOperation({ [weak self] in
            guard let self else { return }

            engine?.detach(self)

        }, { exception in
            Log.error(exception)
        })
    }

    /// Disconnect without breaking other connections.
    public func disconnect(input: AVAudioNode) {
        guard let engine else {
            return
        }

        var newConnections: [AVAudioNode: [AVAudioConnectionPoint]] = [:]

        for bus in 0 ..< numberOfInputs {
            if let cp = engine.inputConnectionPoint(for: self, inputBus: bus) {
                if cp.node === input {
                    let points = engine.outputConnectionPoints(for: input, outputBus: 0)
                    newConnections[input] = points.filter { $0.node != self }
                }
            }
        }

        for (node, connections) in newConnections {
            if connections.isEmpty {
                engine.disconnectNodeOutput(node)
            } else {
                engine.connect(node, to: connections, fromBus: 0, format: AudioDefaults.systemFormat)
            }
        }
    }

    /// Make a connection without breaking other connections.
    public func connect(input: AVAudioNode, bus: Int, format: AVAudioFormat? = nil) {
        guard let engine else {
            return
        }

        let format = format ?? engine.outputFormat

        var points = engine.outputConnectionPoints(for: input, outputBus: 0)

        if points.contains(where: {
            $0.node === self && $0.bus == bus
        }) {
            return
        }

        points.append(AVAudioConnectionPoint(node: self, bus: bus))
        engine.connect(input, to: points, fromBus: 0, format: format)
    }
}
