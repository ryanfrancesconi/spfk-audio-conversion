import Foundation
import SoundAnalysis

/// Result for SoundAnalysis processing
public class SoundClassificationResultObserver: NSObject, SNResultsObserving {
    public private(set) var classifications: [SNClassification]?

    public private(set) var minimumConfidence: Double

    public init(minimumConfidence: Double = SoundClassification.defaultConfidence) {
        self.minimumConfidence = minimumConfidence
    }

    public func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else {
            classifications = nil
            return
        }

        let all = result.classifications
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in
                lhs.confidence > rhs.confidence
            }

        classifications = all
    }
}
