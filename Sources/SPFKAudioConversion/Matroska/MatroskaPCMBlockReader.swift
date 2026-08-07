// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKMatroska

/// Turns a Matroska PCM block into deinterleaved float samples.
///
/// A PCM track needs no decoder — `AVAudioConverter` is not in the path at all — but it does need
/// its samples widened, and 24-bit is why that is done by hand: `AVAudioPCMBuffer` exposes channel
/// data as `Int16`, `Int32`, `Float` or `Double` and has no accessor for a packed 24-bit sample.
struct MatroskaPCMBlockReader: Sendable {
    let bytesPerSample: Int
    let channelCount: Int
    let sampleFormat: MatroskaPCMSampleFormat

    var bytesPerFrame: Int { bytesPerSample * channelCount }

    /// Writes `frameCount` frames from `data` into `output`, starting at the given frame offsets.
    ///
    /// The caller has already established that both ranges are in bounds.
    func write(
        _ data: Data,
        sourceFrameOffset: Int,
        to output: AVAudioPCMBuffer,
        destinationFrameOffset: Int,
        frameCount: Int
    ) {
        guard let channels = output.floatChannelData else { return }

        let outputChannelCount = min(channelCount, Int(output.format.channelCount))

        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            for frame in 0 ..< frameCount {
                let frameStart = (sourceFrameOffset + frame) * bytesPerFrame

                for channel in 0 ..< outputChannelCount {
                    channels[channel][destinationFrameOffset + frame] =
                        value(at: base + frameStart + channel * bytesPerSample)
                }
            }
        }
    }

    /// One sample, as a float in -1...1.
    private func value(at pointer: UnsafePointer<UInt8>) -> Float {
        switch sampleFormat {
        case .float:
            let bits = bits(at: pointer, isBigEndian: false)

            return bytesPerSample == 4
                ? Float(bitPattern: UInt32(truncatingIfNeeded: bits))
                : Float(Double(bitPattern: bits))

        case let .integer(isBigEndian):
            // 8-bit integer PCM is unsigned, following the WAV convention Matroska inherits; every
            // wider depth is two's complement.
            if bytesPerSample == 1 {
                return (Float(pointer.pointee) - 128) / 128
            }

            let raw = bits(at: pointer, isBigEndian: isBigEndian)
            let magnitude = UInt64(1) << (bytesPerSample * 8 - 1)

            // Sign-extend from the sample's own width rather than from 64 bits.
            let signed = raw < magnitude ? Int64(raw) : Int64(raw) - Int64(magnitude) * 2

            return Float(signed) / Float(magnitude)
        }
    }

    /// The sample's bytes as an unsigned integer, in the stream's byte order.
    private func bits(at pointer: UnsafePointer<UInt8>, isBigEndian: Bool) -> UInt64 {
        var bits: UInt64 = 0

        for index in 0 ..< bytesPerSample {
            let byte = UInt64(pointer[isBigEndian ? bytesPerSample - 1 - index : index])
            bits |= byte << (8 * index)
        }

        return bits
    }
}

// MARK: - Matroska

extension MatroskaPCMBlockReader {
    /// `nil` for a track that is not PCM, or is at a width this cannot read.
    init?(track: MatroskaTrack) {
        guard case let .audio(parameters) = track.kind,
              let codec = MatroskaAudioCodec(rawValue: track.codecID),
              let sampleFormat = codec.pcmSampleFormat,
              let bitDepth = parameters.bitDepth,
              parameters.channelCount > 0
        else {
            return nil
        }

        let isSupportedWidth = switch sampleFormat {
        case .float: bitDepth == 32 || bitDepth == 64
        case .integer: bitDepth == 8 || bitDepth == 16 || bitDepth == 24 || bitDepth == 32
        }

        guard isSupportedWidth else { return nil }

        self.init(
            bytesPerSample: bitDepth / 8,
            channelCount: parameters.channelCount,
            sampleFormat: sampleFormat
        )
    }
}
