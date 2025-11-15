import Foundation

/// Persistent struct to store device UIDs
public struct AudioDeviceSettings: Codable, Hashable {
    public static let inputDeviceDisabledUID = "inputDeviceDisabledUID"

    public internal(set) var inputUID: String?
    public internal(set) var outputUID: String?

    public var allowInput: Bool {
        guard let inputUID else { return false }

        return inputUID != Self.inputDeviceDisabledUID
    }

    public init(
        inputUID: String? = nil,
        outputUID: String? = nil
    ) {
        self.inputUID = inputUID
        self.outputUID = outputUID
    }

    public mutating func disableInput() {
        inputUID = Self.inputDeviceDisabledUID
    }
}
