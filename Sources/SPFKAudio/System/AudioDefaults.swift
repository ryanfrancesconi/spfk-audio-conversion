import AVFoundation
import SPFKUtils

public enum AudioDefaults {
    public static let defaultSampleRate: Double = 48000
    public static var minimumSampleRateSupported: Double = 44100

    private static var _systemFormat = AVAudioFormat(
        standardFormatWithSampleRate: defaultSampleRate,
        channels: 2
    ) ?? AVAudioFormat()

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

let kAudioUnitManufacturer_Spongefork = (try? FourCharCode.from(string: "spfk")) ?? 0
let kAudioUnitManufacturer_AudioKit = (try? FourCharCode.from(string: "AuKt")) ?? 0
