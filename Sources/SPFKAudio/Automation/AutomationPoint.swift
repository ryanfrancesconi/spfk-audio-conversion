import AudioToolbox
import Foundation
import OTCore
import SPFKUtils

/// An object to represent one automation point in an UI
public struct AutomationPoint: Equatable, Comparable, Codable, CustomStringConvertible, TypeDescribable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.time < rhs.time
    }

    public var description: String {
        "\(typeName)(time: \(time), gain: \(gain), selected: \(selected), dBMax: \(dBRange.upperBound))"
    }

    public static let dBMin: AUValue = -90

    private var _time: TimeInterval = 0
    public var time: TimeInterval {
        get { _time }
        set {
            _time = max(0, newValue)
        }
    }

    private var _gain: AUValue = 0
    public var gain: AUValue {
        get { _gain }

        set {
            _gain = newValue.clamped(to: gainRange)
            dBValue = _gain.dBValue.clamped(to: dBRange).rounded(decimalPlaces: 2)
            updateLabel()
        }
    }

    /// Will be updated based on gain
    public private(set) var dBValue: AUValue = 0

    /// Default is 0 ... +12dB, or 0 ... 4 linear gain
    public private(set) var gainRange: ClosedRange<AUValue> = Fader.defaultGainRange

    /// Default is 0 ... +12dB
    public private(set) var dBRange: ClosedRange<AUValue> = (dBMin ... 12) {
        didSet {
            updateRange()
        }
    }

    /// If the user has clicked on this point in the UI
    public var selected: Bool = false

    /// A string suitable for displaying in the UI such as "+6.0 dB"
    public private(set) var label: String = ""

    public init(time: TimeInterval, gain: AUValue, selected: Bool = false, dBMax: AUValue = 12) {
        self.dBRange = Self.dBMin ... dBMax
        self.time = time
        self.gain = gain
        self.selected = selected

        updateRange()
    }

    private mutating func updateRange() {
        gainRange = 0 ... dBRange.upperBound.linearValue
    }

    private mutating func updateLabel() {
        label = dBValue.dBString(decimalPlaces: 1)
    }
}
