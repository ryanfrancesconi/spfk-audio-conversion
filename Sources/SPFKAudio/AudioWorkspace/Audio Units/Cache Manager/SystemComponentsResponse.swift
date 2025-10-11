

import Foundation

public struct SystemComponentsResponse {
    public var results = [ComponentValidationResult]()

    public init(results: [ComponentValidationResult] = []) {
        self.results = results
    }
}
