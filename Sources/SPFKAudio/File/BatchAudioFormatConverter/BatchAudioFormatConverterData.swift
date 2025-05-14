// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

public actor BatchAudioFormatConverterData {
    public private(set) var sources: [AudioFormatConverterSource] = []
    public private(set) var count: Int = 0
    public private(set) var batchSize: Int = 0
    public private(set) var completed: Int = 0

    public var percent: ProgressValue1 {
        guard count > 0 else { return 0 }

        return completed.double / count.double
    }

    public init() {}

    public init(sources: [AudioFormatConverterSource]) async {
        update(sources: sources)
    }

    public func update(sources: [AudioFormatConverterSource]) {
        self.sources = sources
        count = sources.count
        batchSize = 8.clamped(to: 0 ... count)
    }

    public func increment() {
        completed += 1
    }
}
