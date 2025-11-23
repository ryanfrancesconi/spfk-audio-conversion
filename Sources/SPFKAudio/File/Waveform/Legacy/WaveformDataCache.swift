// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKBase

/// Actor isolated cached waveform data keyed by `URL` or `String`
public actor WaveformDataCache {
    public private(set) var data: WaveformDataCollection
    public subscript(key: String) -> WaveformData? { data[key] }
    public subscript(url: URL) -> WaveformData? { data[url.path] }

    public init() {
        data = WaveformDataCollection()
    }

    public init(collection: WaveformDataCollection) {
        self.data = collection
    }

    public func insert(value: WaveformData, for url: URL) {
        insert(value: value, for: url.path)
    }

    public func insert(value: WaveformData, for key: String) {
        data[key] = value
    }

    public func contains(url: URL) -> Bool {
        contains(key: url.path)
    }

    public func contains(key: String) -> Bool {
        data[key] != nil
    }

    // subscript access

    public func get(url: URL) -> WaveformData? {
        get(key: url.path)
    }

    public func get(key: String) -> WaveformData? {
        data[key]
    }
}
