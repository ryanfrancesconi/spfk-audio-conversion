
import AudioToolbox
import Foundation

public struct AutomationPoint: Equatable, Comparable, Codable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.time < rhs.time
    }

    public static let dBMin: AUValue = -90

    public private(set) var dBRange: ClosedRange<AUValue> = (dBMin ... 12) {
        didSet {
            updateRange()
        }
    }

    public var linearRange: ClosedRange<AUValue> = Fader.defaultGainRange

    public var taper: AUValue = FadeDescription.AudioTaper.taper.in

    public var time: Double = 0 {
        didSet {
            time = max(0, time)
        }
    }

    public private(set) var dBValue: AUValue = 0

    public private(set) var description: String = ""

    public var selected: Bool = false

    private var _gain: AUValue = 0

    public var gain: AUValue {
        get {
            _gain
        }
        set {
            let newValue = newValue.clamped(to: linearRange)
            _gain = newValue

            dBValue = newValue.dBValue.rounded(decimalPlaces: 2)
            dBValue = dBValue.clamped(to: dBRange)

            updateDBString()
        }
    }

    public private(set) var string: String = ""

    public init(time: Double, gain: AUValue, selected: Bool = false, dBMax: AUValue) {
        dBRange = Self.dBMin ... dBMax
        updateRange()

        self.time = time
        self.gain = gain
        self.selected = selected
    }

    private mutating func updateRange() {
        linearRange = 0 ... dBRange.upperBound.linearValue
    }

    private mutating func updateDBString() {
        description = dBValue.dBString(decimalPlaces: 1)
    }
}
