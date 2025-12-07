// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio
// Inspired by AudioKit's implementation. Revision History at http://github.com/AudioKit/AudioKit/

import AudioToolbox
import AVFoundation
import SPFKAUHost

public protocol AudioEngineNodeAU: AudioEngineNode {
    var avAudioNode: AVAudioNode { get }
}

extension AudioEngineNodeAU {
    /// All parameters on the Node
    public var parameters: [NodeParameter] {
        let mirror = Mirror(reflecting: self)
        var params: [NodeParameter] = []

        for child in mirror.children {
            if let param = child.value as? ParameterBase {
                params.append(param.projectedValue)
            }
        }

        return params
    }

    /// Set up node parameters using reflection
    public func setupParameters() {
        let mirror = Mirror(reflecting: self)
        var params: [AUParameter] = []

        for child in mirror.children {
            guard let param = child.value as? ParameterBase else { continue }

            let def = param.projectedValue.def

            let auParam = AUParameterTree.createParameter(
                identifier: def.identifier,
                name: def.name,
                address: def.address,
                range: def.range,
                unit: def.unit,
                flags: def.flags
            )

            params.append(auParam)

            param.projectedValue.associate(with: avAudioNode, parameter: auParam)
        }

        avAudioNode.auAudioUnit.parameterTree = AUParameterTree.createTree(withChildren: params)
    }
}
