// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AudioToolbox
import AVFoundation
import Foundation

/// Decodes compressed packets through a bare `AudioConverter`, for the configurations
/// `AVAudioConverter` cannot decode.
///
/// **Multichannel Opus is the one known case.** Measured 2026-11-01: `AVAudioConverter` consumes
/// every 5.1 Opus packet and emits nothing, with the `OpusHead` cookie on the format, on the
/// converter, or both; a bare converter given the same cookie through
/// `kAudioConverterDecompressionMagicCookie` decodes them.
///
/// Holds the packet being decoded until the converter asks for the next one, because the converter
/// reads it after the input callback returns. One consumer only, like the decoder that owns it.
final class MatroskaRawAudioConverter {
    private let converter: AudioConverterRef
    private let outputFormat: AVAudioFormat

    private var packetStorage: UnsafeMutableRawPointer?
    private var packetCapacity = 0
    private let packetDescription = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)

    /// Supplies the next packet, or `nil` at the end of the track.
    private var nextPacket: (() throws -> Data?)?
    private var supplyError: (any Error)?
    private var sourceExhausted = false

    /// - Throws: ``MatroskaAudioDecoderError/decoderUnavailable(_:)`` when Core Audio refuses the
    ///   formats or the cookie.
    init(
        input: AudioStreamBasicDescription,
        output: AVAudioFormat,
        magicCookie: Data?,
        codecID: String
    ) throws {
        var input = input
        var converter: AudioConverterRef?

        guard AudioConverterNew(&input, output.streamDescription, &converter) == noErr, let converter else {
            throw MatroskaAudioDecoderError.decoderUnavailable(codecID)
        }

        self.converter = converter
        outputFormat = output

        if let magicCookie, magicCookie.isEmpty == false {
            let status = magicCookie.withUnsafeBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return kAudioConverterErr_BadPropertySizeError }

                return AudioConverterSetProperty(
                    converter,
                    kAudioConverterDecompressionMagicCookie,
                    UInt32(bytes.count),
                    base
                )
            }

            guard status == noErr else {
                AudioConverterDispose(converter)
                throw MatroskaAudioDecoderError.decoderUnavailable(codecID)
            }
        }
    }

    deinit {
        AudioConverterDispose(converter)
        packetStorage?.deallocate()
        packetDescription.deallocate()
    }

    /// Discards decoder state, for a seek.
    func reset() {
        AudioConverterReset(converter)
        sourceExhausted = false
    }

    /// Fills `buffer` from packets `nextPacket` supplies.
    ///
    /// - Returns: whether the source ran out during this call. The buffer may still hold frames.
    func convert(into buffer: AVAudioPCMBuffer, nextPacket: @escaping () throws -> Data?) throws -> Bool {
        guard sourceExhausted == false else {
            buffer.frameLength = 0
            return true
        }

        self.nextPacket = nextPacket
        supplyError = nil
        defer { self.nextPacket = nil }

        var frames = buffer.frameCapacity
        buffer.frameLength = buffer.frameCapacity

        let status = AudioConverterFillComplexBuffer(
            converter,
            Self.inputProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &frames,
            buffer.mutableAudioBufferList,
            nil
        )

        buffer.frameLength = frames

        if let supplyError {
            throw supplyError
        }

        guard status == noErr else {
            throw MatroskaAudioDecoderError.decoderUnavailable("AudioConverter status \(status)")
        }

        return sourceExhausted
    }

    /// One packet per call. Returning zero packets with `noErr` tells the converter the stream has
    /// ended, so it flushes what it holds.
    private static let inputProc: AudioConverterComplexInputDataProc = { _, ioPacketCount, ioData, outDescriptions, userData in
        guard let userData else {
            ioPacketCount.pointee = 0
            return noErr
        }

        let decoder = Unmanaged<MatroskaRawAudioConverter>.fromOpaque(userData).takeUnretainedValue()

        let packet: Data?

        do {
            packet = try decoder.nextPacket?()
        } catch {
            decoder.supplyError = error
            packet = nil
        }

        guard let packet, packet.isEmpty == false else {
            decoder.sourceExhausted = true
            ioPacketCount.pointee = 0
            return noErr
        }

        decoder.store(packet)

        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mData = decoder.packetStorage
        ioData.pointee.mBuffers.mDataByteSize = UInt32(packet.count)
        ioData.pointee.mBuffers.mNumberChannels = decoder.outputFormat.channelCount

        decoder.packetDescription.pointee = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 0,
            mDataByteSize: UInt32(packet.count)
        )

        outDescriptions?.pointee = decoder.packetDescription

        ioPacketCount.pointee = 1
        return noErr
    }

    private func store(_ packet: Data) {
        if packet.count > packetCapacity {
            packetStorage?.deallocate()
            packetStorage = UnsafeMutableRawPointer.allocate(byteCount: packet.count, alignment: 16)
            packetCapacity = packet.count
        }

        guard let packetStorage else { return }

        packet.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            packetStorage.copyMemory(from: base, byteCount: packet.count)
        }
    }
}
