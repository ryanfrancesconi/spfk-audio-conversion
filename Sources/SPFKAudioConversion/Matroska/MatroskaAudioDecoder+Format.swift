// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKMatroska

extension MatroskaAudioDecoder {
    /// The PCM format a track decodes into, and what decodes it.
    ///
    /// **More than two channels need the layout the decoder outputs**: Core Audio maps a decoder's
    /// channels onto the output by label, and a discrete output layout matches none of them and
    /// decodes silence. A track whose layout is not known is refused rather than decoded silent.
    static func makeDecodePath(
        url: URL,
        track: MatroskaTrack,
        codec: Codec,
        parameters: MatroskaTrack.AudioParameters
    ) throws -> (AVAudioFormat, Path) {
        let channelCount = AVAudioChannelCount(parameters.channelCount)

        let firstPacket = track.needsFirstPacketForChannelLayout
            ? try MatroskaFrameReader.firstPacket(url: url, trackNumber: track.number)
            : nil

        let layoutTag = track.audioChannelLayoutTag(firstPacket: firstPacket)

        if codec.pcmSampleFormat != nil {
            guard track.hasUnsupportedContentEncoding == false,
                  let blockReader = MatroskaPCMBlockReader(track: track),
                  let format = AVAudioFormat.pcmProcessingFormat(
                      sampleRate: parameters.sampleRate,
                      channelCount: channelCount,
                      layoutTag: layoutTag
                  )
            else {
                throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
            }

            return (format, .pcm(blockReader))
        }

        guard channelCount <= 2 || layoutTag != nil else {
            throw MatroskaAudioDecoderError.unsupportedChannelLayout(codecID: track.codecID, channelCount: Int(channelCount))
        }

        guard let processingFormat = AVAudioFormat.pcmProcessingFormat(
            sampleRate: parameters.sampleRate,
            channelCount: channelCount,
            layoutTag: layoutTag
        ) else {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        // The description comes from `spfk-matroska` rather than being rebuilt here: FLAC's packet
        // length and source depth are read from the file, and a second copy of that reading is how
        // one path decodes and the other returns silence.
        let formatDescription: CMAudioFormatDescription

        do {
            formatDescription = try track.makeAudioFormatDescription(firstPacket: firstPacket)
        } catch {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        if codec == .opus, channelCount > 2 {
            guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
                throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
            }

            let converter = try MatroskaRawAudioConverter(
                input: streamDescription,
                output: processingFormat,
                magicCookie: track.codecPrivate,
                codecID: track.codecID
            )

            return (processingFormat, .rawConverter(converter))
        }

        let compressedFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        guard let converter = AVAudioConverter(from: compressedFormat, to: processingFormat) else {
            throw MatroskaAudioDecoderError.decoderUnavailable(track.codecID)
        }

        return (processingFormat, .converter(converter, compressedFormat: compressedFormat))
    }
}
