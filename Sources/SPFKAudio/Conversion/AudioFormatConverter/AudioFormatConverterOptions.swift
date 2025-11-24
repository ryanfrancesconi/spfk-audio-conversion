// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKAudioBase
import SPFKMetadata
import SPFKUtils

/// The conversion options. In general, leave any property nil to adopt the value of the input file.
/// bitRate assumes a stereo bit rate and the converter will half it for mono
public struct AudioFormatConverterOptions {
    public static let bitsPerChannelRange: ClosedRange<UInt32> = 16 ... 32
    public static let bitRange: ClosedRange<UInt32> = 64000 ... 320000

    /// An option to block upsampling to a higher bit depth than the source.
    /// For example, converting to 24bit from 16 doesn't have much benefit
    public enum BitDepthRule: String, Codable {
        public typealias RawValue = String

        /// Don't allow upsampling to 24bit if the src is 16
        case lessThanOrEqual

        /// allow any conversaion
        case any
    }

    private var _format: AudioFileType?

    /// Audio Format as a string
    public var format: AudioFileType? {
        get { _format }

        set {
            // enforce format to be a file extension
            guard let newValue,
                  AudioFormatConverter.outputFormats.contains(newValue) else {
                _format = nil
                return
            }

            _format = newValue
        }
    }

    /// Sample Rate in Hertz
    public var sampleRate: Double?

    /// used only with PCM data
    private var _bitsPerChannel: UInt32?
    public var bitsPerChannel: UInt32? {
        get { _bitsPerChannel }
        set {
            if let newValue, newValue < Self.bitsPerChannelRange.lowerBound {
                Log.error("bitsPerChannel is too low and will be clamped", newValue)
            }

            _bitsPerChannel = newValue?.clamped(to: Self.bitsPerChannelRange)
        }
    }

    /// bytes per second: used only when outputting compressed audio
    public var bitRate: UInt32 = 256000 {
        didSet {
            if bitRate < Self.bitRange.lowerBound {
                assertionFailure("bitRate is too low \(bitRate) and will be clamped to \(Self.bitRange). Did you *= 1000?")
            }

            bitRate = bitRate.clamped(to: Self.bitRange)
        }
    }

    /// An option to block upsampling to a higher bit depth than the source.
    /// default value is `.any`
    public var bitDepthRule: BitDepthRule = .any

    /// How many channels to convert to. Typically 1 or 2
    public var channels: UInt32?

    /// Maps to PCM Convertion format option `AVLinearPCMIsNonInterleaved`
    public var isInterleaved: Bool?

    /// Overwrite existing files, set false if you want to handle this before you call start()
    public var eraseFile: Bool = true

    public init() {}

    /// Create options by parsing the contents of the url and using the audio settings
    /// in the file
    /// - Parameter url: The audio file to open and parse
    public init?(url: URL) {
        guard let avFile = try? AVAudioFile(forReading: url) else { return nil }
        self.init(audioFile: avFile)
    }

    /// Create options by parsing the audioFile for its settings
    /// - Parameter audioFile: an AVAudioFile to parse
    public init?(audioFile: AVAudioFile) {
        let streamDescription = audioFile.fileFormat.streamDescription.pointee

        format = AudioFileType(rawValue: audioFile.url.pathExtension.lowercased())
        sampleRate = streamDescription.mSampleRate
        bitsPerChannel = streamDescription.mBitsPerChannel
        channels = streamDescription.mChannelsPerFrame
    }

    /// Create PCM Options
    /// - Parameters:
    ///   - pcmFormat: wav, aif, or caf
    ///   - sampleRate: Sample Rate
    ///   - bitDepth: Bit Depth, or bits per channel
    ///   - channels: How many channels
    public init(
        pcmFormat: AudioFileType,
        sampleRate: Double? = nil,
        bitsPerChannel: UInt32? = nil,
        channels: UInt32? = nil,
        bitDepthRule: BitDepthRule = .any
    ) throws {
        guard pcmFormat.isPCM else {
            throw NSError(description: "Not a pcm format \(pcmFormat.pathExtension)")
        }

        format = pcmFormat
        self.sampleRate = sampleRate
        self.bitsPerChannel = bitsPerChannel
        self.channels = channels
        self.bitDepthRule = bitDepthRule
    }

    public init(format: AudioFileType) {
        self.format = format
    }
}

extension AudioFormatConverterOptions: Serializable {
    public init(data: Data) throws {
        self = try PropertyListDecoder().decode(AudioFormatConverterOptions.self, from: data)
    }
}

extension AudioFormatConverterOptions {
    public static var waveStereo48k16bit: AudioFormatConverterOptions {
        get async {
            var o = AudioFormatConverterOptions()
            o.format = .wav
            o.sampleRate = await AudioDefaults.shared.sampleRate
            o.bitsPerChannel = 16
            o.channels = 2
            o.bitDepthRule = .any
            return o
        }
    }
}
