//  Copyright © 2021 Audio Design Desk. All rights reserved.

import AudioToolbox
import AVFoundation

public protocol EngineNodeAU: EngineNode {
    var avAudioNode: AVAudioNode { get }
}

public extension EngineNodeAU {
    /// All parameters on the Node
    var parameters: [NodeParameter] {
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
    func setupParameters() {
        let mirror = Mirror(reflecting: self)
        var params: [AUParameter] = []

        for child in mirror.children {
            if let param = child.value as? ParameterBase {
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
        }

        avAudioNode.auAudioUnit.parameterTree = AUParameterTree.createTree(withChildren: params)
    }
}
