// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKBase
import SPFKMatroska

/// Decodes a Matroska or WebM file's audio track to PCM.
///
/// Exists because AVFoundation cannot open the container at all, so `AVAudioFile` and
/// `ExtAudioFile` — everything else in this package's decode path — throw `'fmt?'` on a `.mkv`.
/// `spfk-matroska` supplies the compressed frames and this turns them into PCM.
///
/// **Decoding is Apple's, never ours.** The codecs here are pool-licensed and macOS already ships
/// decoders for them; this feeds `AVAudioConverter` and gets PCM back.
///
/// Sequential by design: frames come out of the demuxer in stored order and there is no seek. That
/// suits the callers — a waveform scan reads front to back — and avoids holding a whole film's
/// audio in memory, which at 48kHz stereo float is roughly 1.4GB per hour.
public final class MatroskaAudioDecoder {
    /// Codecs this decoder can hand to `AVAudioConverter`.
    ///
    /// Deliberately a small set. Matroska admits codecs macOS has no decoder for (DTS, and TrueHD
    /// among others), and a caller needs "cannot decode this" to be an answer rather than silence.
    public enum Codec: String, Sendable, CaseIterable {
        case aac = "A_AAC"
        case mp3 = "A_MPEG/L3"
        case ac3 = "A_AC3"
        case flac = "A_FLAC"
        case pcmIntegerLittleEndian = "A_PCM/INT/LIT"

        var formatID: AudioFormatID {
            switch self {
            case .aac: kAudioFormatMPEG4AAC
            case .mp3: kAudioFormatMPEGLayer3
            case .ac3: kAudioFormatAC3
            case .flac: kAudioFormatFLAC
            case .pcmIntegerLittleEndian: kAudioFormatLinearPCM
            }
        }

        /// Frames per compressed packet, which the converter needs up front because a compressed
        /// format cannot state bytes-per-frame.
        var framesPerPacket: UInt32 {
            switch self {
            case .aac: 1024
            case .mp3: 1152
            case .ac3: 1536
            case .flac, .pcmIntegerLittleEndian: 0
            }
        }
    }

    public let url: URL

    /// The Matroska track being decoded.
    public let track: MatroskaTrack

    /// The PCM format frames are decoded into — deinterleaved 32-bit float at the track's own rate,
    /// which is what the waveform and the audio engine both consume.
    public let processingFormat: AVAudioFormat

    private let reader: MatroskaFrameReader
    private let compressedFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private var reachedEnd = false

    /// Opens `url` and prepares to decode its first audio track.
    ///
    /// - Throws: ``MatroskaAudioDecoderError`` when the file has no audio, or its codec is one
    ///   macOS cannot decode.
    public init(url: URL) throws {
        self.url = url

        reader = try MatroskaFrameReader(url: url)

        guard let track = reader.file.audioTrack else {
            throw MatroskaAudioDecoderError.noAudioTrack(url)
        }

        guard case let .audio(parameters) = track.kind else {
            throw MatroskaAudioDecoderError.noAudioTrack(url)
        }

        guard let codec = Codec(rawValue: track.codecID) else {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        self.track = track

        var description = AudioStreamBasicDescription(
            mSampleRate: parameters.sampleRate,
            mFormatID: codec.formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: codec.framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(parameters.channelCount),
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let compressedFormat = AVAudioFormat(streamDescription: &description) else {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        guard let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: parameters.sampleRate,
            channels: AVAudioChannelCount(parameters.channelCount)
        ) else {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        guard let converter = AVAudioConverter(from: compressedFormat, to: processingFormat) else {
            throw MatroskaAudioDecoderError.decoderUnavailable(track.codecID)
        }

        self.compressedFormat = compressedFormat
        self.processingFormat = processingFormat
        self.converter = converter
    }

    /// Decodes up to `frameCapacity` frames, or `nil` once the track is exhausted.
    ///
    /// A returned buffer can hold fewer frames than asked for without meaning the end — the
    /// converter emits what a whole number of packets produced.
    public func nextBuffer(frameCapacity: AVAudioFrameCount = 8192) throws -> AVAudioPCMBuffer? {
        if reachedEnd {
            return nil
        }

        guard let output = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCapacity) else {
            throw MatroskaAudioDecoderError.bufferAllocationFailed
        }

        var demuxError: (any Error)?

        let status = converter.convert(to: output, error: nil) { [weak self] _, statusOut in
            guard let self else {
                statusOut.pointee = .endOfStream
                return nil
            }

            do {
                guard let packet = try nextPacket() else {
                    statusOut.pointee = .endOfStream
                    return nil
                }

                statusOut.pointee = .haveData
                return packet

            } catch {
                demuxError = error
                statusOut.pointee = .endOfStream
                return nil
            }
        }

        if let demuxError {
            throw demuxError
        }

        switch status {
        case .endOfStream:
            reachedEnd = true
            return output.frameLength > 0 ? output : nil

        case .error:
            throw MatroskaAudioDecoderError.decodeFailed(url)

        default:
            return output.frameLength > 0 ? output : nil
        }
    }

    /// The next compressed packet for this track, skipping the interleaved video and subtitle
    /// frames the demuxer hands back alongside it.
    private func nextPacket() throws -> AVAudioCompressedBuffer? {
        while let frame = try reader.nextFrame() {
            guard frame.trackNumber == track.number, frame.data.isEmpty == false else {
                continue
            }

            let byteCount = frame.data.count

            let buffer = AVAudioCompressedBuffer(
                format: compressedFormat,
                packetCapacity: 1,
                maximumPacketSize: byteCount
            )

            frame.data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                buffer.data.copyMemory(from: base, byteCount: byteCount)
            }

            buffer.byteLength = UInt32(byteCount)
            buffer.packetCount = 1

            // Matroska stores one whole packet per frame with no framing header, so the description
            // is the trivial one -- but it has to be present, or the converter reads a packet size
            // of zero and produces nothing.
            buffer.packetDescriptions?.pointee = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(byteCount)
            )

            return buffer
        }

        return nil
    }
}
