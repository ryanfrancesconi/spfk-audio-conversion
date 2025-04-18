import AVFoundation
import Foundation

public struct TransientCollection {
    public private(set) var transients: [Transient]
    public private(set) var threshold: Float
    public private(set) var transientsAboveThreshold: [Transient]
    public private(set) var transientsBelowThreshold: [Transient]

    public init(transients: [Transient], threshold: Float) {
        self.transients = transients
        self.threshold = threshold

        transientsAboveThreshold = transients.filter { $0.passesThreshold }
        transientsBelowThreshold = transients.filter { !$0.passesThreshold }
    }
}
