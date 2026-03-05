// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioBase
import SPFKMetadata
import SPFKUtils

/// Options controlling an audio format conversion.
///
/// Leave any property `nil` to adopt the corresponding value from the input file.
/// `bitRate` assumes a stereo bit rate; the converter halves it for mono output.
public struct AudioFormatConverterOptions: Sendable {
    /// Allowed range for ``bitsPerChannel`` (16–32).
    public static let bitsPerChannelRange: ClosedRange<UInt32> = 16 ... 32

    /// Allowed range for ``bitRate`` in bits per second (64 000–320 000).
    public static let bitRange: ClosedRange<UInt32> = 64000 ... 320_000

    /// Controls whether the converter may increase the bit depth beyond the source.
    public enum BitDepthRule: String, Codable, Sendable {
        public typealias RawValue = String

        /// Clamp the output bit depth to the source value (e.g. 16-bit source stays 16-bit).
        case lessThanOrEqual

        /// Allow any bit depth conversion, including upsampling.
        case any
    }

    private var _format: AudioFileType?

    /// The target audio file format. Only values in ``AudioFormatConverter/outputFormats`` are accepted.
    public var format: AudioFileType? {
        get { _format }

        set {
            // enforce format to be a file extension
            guard let newValue,
                  AudioFormatConverter.outputFormats.contains(newValue)
            else {
                _format = nil
                return
            }

            _format = newValue
        }
    }

    /// Sample Rate in Hertz
    public var sampleRate: Double?

    /// Bits per channel for PCM output (clamped to ``bitsPerChannelRange``).
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

    /// Encoder bit rate in bits per second for compressed output (clamped to ``bitRange``).
    public var bitRate: UInt32 = 256_000 {
        didSet {
            if bitRate < Self.bitRange.lowerBound {
                Log.error("bitRate is too low \(bitRate) and will be clamped to \(Self.bitRange). Did you *= 1000? Will be clamped to \(Self.bitRange)")
            }

            bitRate = bitRate.clamped(to: Self.bitRange)
        }
    }

    /// Controls whether bit depth upsampling is allowed. Defaults to ``BitDepthRule/any``.
    public var bitDepthRule: BitDepthRule = .any

    /// Target channel count, or `nil` to preserve the source channel layout.
    public var channels: UInt32?

    /// Maps to PCM Conversion format option `AVLinearPCMIsNonInterleaved`
    public var isInterleaved: Bool?

    /// Whether to overwrite an existing output file. Set to `false` to receive an error instead.
    public var eraseFile: Bool = true

    /// Creates default options (all values `nil`, adopting the input file's properties).
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

    /// Creates options targeting the given format with all other values at their defaults.
    public init(format: AudioFileType) {
        self.format = format
    }
}

extension AudioFormatConverterOptions: Serializable {}

extension AudioFormatConverterOptions {
    /// Preset: stereo 16-bit WAV at the system default sample rate.
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
