// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import CoreAudio
import Foundation

/// Common audio formats that `AudioFormatConverter` can handle
public enum AudioFileType: String, Codable, CaseIterable {
    case aac
    case aifc
    case aiff
    case au
    case snd
    case caf
    case m4a
    case m4v
    case mov
    case mp3
    case mp4
    case sd2
    case ts
    case unknown = ""
    case wav

    public var pathExtension: String { rawValue }

    public init(pathExtension: String) {
        let rawValue = pathExtension.lowercased()

        if rawValue == "aif" {
            self = .aiff
            return
        }

        // otherwise the pathExtension should match the rawValue
        guard let value = AudioFileType(rawValue: rawValue) else {
            self = .unknown // no pathExtension or unmatched
            return
        }

        self = value
    }

    // MARK: - Convenience onversions mappings to CoreAudio and AVFoundation types where possible

    /// AVFoundation: File format UTIs
    public var avFileType: AVFileType? {
        switch self {
        case .wav: return .wav
        case .aiff: return .aiff
        case .aifc: return .aifc
        case .caf: return .caf
        case .m4a: return .m4a
        case .mp3: return .mp3
        case .aac: return .mp4
        case .m4v: return .m4v
        case .mov: return .mov
        case .mp4: return .mp4

        default:
            return nil
        }
    }

    public var utType: UTType {
        if let utType = UTType(filenameExtension: pathExtension) {
            return utType
        }

        return .data
    }

    public var isPCM: Bool {
        audioFormatID == kAudioFormatLinearPCM
    }

    /// CoreAudio: A four char code indicating the general kind of data in the stream.
    public var audioFormatID: AudioFormatID? {
        switch self {
        case .wav, .aifc, .aiff, .caf:
            return kAudioFormatLinearPCM
        case .m4a, .mp4:
            return kAudioFormatMPEG4AAC
        case .mp3:
            return kAudioFormatMPEGLayer3
        case .aac:
            return kAudioFormatMPEG4AAC

        default:
            return nil
        }
    }

    /// CoreAudio: Identifier for an audio file type.
    public var audioFileTypeID: AudioFileTypeID? {
        switch self {
        case .wav: return kAudioFileWAVEType
        case .aiff: return kAudioFileAIFFType
        case .aifc: return kAudioFileAIFCType
        case .caf: return kAudioFileCAFType
        case .sd2: return kAudioFileSoundDesigner2Type
        case .mp3: return kAudioFileMP3Type
        case .aac: return kAudioFileAAC_ADTSType
        case .mp4: return kAudioFileMPEG4Type
        case .m4a: return kAudioFileM4AType

        default:
            return nil
        }
    }
}
