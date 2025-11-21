import AVFoundation
import SPFKUtils

public enum AudioDefaults {
    public static let defaultSampleRate: Double = 48000

    public static var minimumSampleRateSupported: Double = 44100

    public static var enforceMinimumSamplateRate = false

    private static var _systemFormat = AVAudioFormat(
        standardFormatWithSampleRate: defaultSampleRate,
        channels: 2
    ) ?? AVAudioFormat()

    public static func isSupported(sampleRate: Double) -> Bool {
        guard enforceMinimumSamplateRate else {
            return sampleRate > 0
        }

        return sampleRate >= AudioDefaults.minimumSampleRateSupported
    }

    public static var systemFormat: AVAudioFormat {
        get { _systemFormat }
        set {
            guard newValue.sampleRate >= minimumSampleRateSupported else {
                Log.debug(newValue.sampleRate, "isn't a supported sample rate, so ignoring this setting")
                return
            }

            _systemFormat = newValue
        }
    }

    public static var sampleRate: Double {
        systemFormat.sampleRate
    }
}

let kAudioUnitManufacturer_Spongefork: FourCharCode = "spfk".fourCC ?? 0
let kAudioUnitManufacturer_AudioKit: FourCharCode = "AuKt".fourCC ?? 0
