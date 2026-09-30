// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AudioToolbox
import Foundation
import SPFKAudioBase
import SPFKBase

extension AudioFormatConverter {
    /// The most channels each direct-encoder output takes, past which the input is downmixed first.
    static func maximumChannels(for format: AudioFileType?) -> UInt32 {
        switch format {
        case .flac, .ogg, .opus: 8
        default: 2
        }
    }

    /// Makes `file` mix its channels down to `channels` on read, rather than keeping the first
    /// `channels` and dropping the rest.
    ///
    /// Call after the client data format is set. The mix follows the file's channel layout, so 5.1
    /// folds its center and surrounds into stereo; the LFE is left out, as a stereo downmix does.
    static func enableDownmix(on file: ExtAudioFileRef, to channels: UInt32) throws {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 1
            ? kAudioChannelLayoutTag_Mono
            : channels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_DiscreteInOrder | channels

        try check(
            ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ClientChannelLayout,
                UInt32(MemoryLayout<AudioChannelLayout>.size),
                &layout
            ),
            "set the downmix channel layout"
        )

        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)

        try check(
            ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &size, &converter),
            "read the file's converter"
        )

        guard let converter else {
            throw NSError(description: "Unable to downmix: the input file has no converter")
        }

        var performDownmix: UInt32 = 1

        try check(
            AudioConverterSetProperty(
                converter,
                kAudioConverterPropertyPerformDownmix,
                UInt32(MemoryLayout<UInt32>.size),
                &performDownmix
            ),
            "enable the downmix"
        )

        // ExtAudioFile keeps its own copy of the converter's settings; a nil config makes it take
        // the one just changed.
        var config: CFArray?

        try check(
            ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ConverterConfig,
                UInt32(MemoryLayout<CFArray?>.size),
                &config
            ),
            "apply the downmix"
        )
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            throw NSError(code: Int(status), description: "Unable to \(step) (error \(status))")
        }
    }
}
