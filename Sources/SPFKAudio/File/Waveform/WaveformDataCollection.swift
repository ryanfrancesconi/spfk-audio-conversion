// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation
import SPFKUtils

/// Wrapper on array to implement Serializable. This object can be saved persistently between runs
/// and a new `WaveformDataCache` formed on startup.
public struct WaveformDataCollection: Serializable, Equatable {
    public typealias Storage = [String: WaveformData]

    private(set) var collection: Storage

    public subscript(key: String) -> WaveformData? {
        get { collection[key] }
        set { collection[key] = newValue }
    }

    public subscript(url: URL) -> WaveformData? {
        get { self[url.path] }
        set {
            self[url.path] = newValue
        }
    }

    public init() {
        collection = .init()
    }

    public init(collection: Storage) {
        self.collection = collection
    }
}
