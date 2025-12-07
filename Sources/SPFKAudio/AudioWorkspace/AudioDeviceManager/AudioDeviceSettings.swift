// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Foundation

/// Persistent struct to store device UIDs
public actor AudioDeviceSettings {
    public static let inputDeviceDisabledUID = "inputDeviceDisabledUID"

    public var inputUID: String?
    public var outputUID: String?

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

    public func update(inputUID: String?) {
        self.inputUID = inputUID
    }

    public func update(outputUID: String?) {
        self.outputUID = inputUID
    }

    public func disableInput() {
        inputUID = Self.inputDeviceDisabledUID
    }
}
