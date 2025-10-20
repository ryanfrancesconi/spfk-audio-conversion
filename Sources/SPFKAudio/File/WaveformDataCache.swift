import Foundation
import SPFKUtils

public typealias WaveformDataCacheCollection = [String: WaveformData]

public actor WaveformDataCache {
    public private(set) var collection: WaveformDataCacheCollection

    public subscript(key: String) -> WaveformData? { collection[key] }
    public subscript(url: URL) -> WaveformData? { collection[url.path] }

    public init() {
        collection = WaveformDataCacheCollection()
    }

    public init(collection: WaveformDataCacheCollection) {
        self.collection = collection
    }

    public init(data: Data) throws {
        collection = try PropertyListDecoder().decode(WaveformDataCacheCollection.self, from: data)
    }

    /// helper function to encode async due to async isolation which is incompatible with Encodable
    public func encode() throws -> Data? {
        try PropertyListEncoder().encode(collection)
    }

    public func insert(value: WaveformData, for url: URL) {
        insert(value: value, for: url.path)
    }

    public func insert(value: WaveformData, for key: String) {
        collection[key] = value
    }

    public func contains(url: URL) -> Bool {
        contains(key: url.path)
    }

    public func contains(key: String) -> Bool {
        collection[key] != nil
    }

    public func get(url: URL) -> WaveformData? {
        get(key: url.path)
    }

    public func get(key: String) -> WaveformData? {
        collection[key]
    }
}
