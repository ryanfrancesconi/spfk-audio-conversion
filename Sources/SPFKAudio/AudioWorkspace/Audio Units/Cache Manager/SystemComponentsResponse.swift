

import Foundation

public struct SystemComponentsResponse: Sendable {
    public let results: [ComponentValidationResult]

    public init(results: [ComponentValidationResult] = []) {
        self.results = results
    }
}
