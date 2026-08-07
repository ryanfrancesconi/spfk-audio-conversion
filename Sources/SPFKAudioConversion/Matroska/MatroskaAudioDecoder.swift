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
/// Streamed rather than loaded: frames come out of the demuxer in stored order and are decoded as
/// asked for, so a whole film's audio never exists in memory at once — at 48kHz stereo float that
/// would be roughly 1.4GB per hour.
///
/// ``seek(toFrame:)`` repositions through the container's `Cues` index, which is what makes this
/// usable for playback as well as for the front-to-back waveform scan it was first written for.
/// `@unchecked Sendable` on exactly the terms `MatroskaSampleBufferReader` is: this holds a position
/// in a file, so **one consumer may drive it and no more** — two threads pulling from it would
/// interleave their reads. The conformance exists so a player can hand it to a feed `Task`, and is a
/// statement of that invariant rather than a claim of thread safety.
public final class MatroskaAudioDecoder: @unchecked Sendable {
    /// The codec table moved to `spfk-matroska` (2026-08-06) once the sample-buffer path needed
    /// the same mapping — one table rather than two that drift.
    public typealias Codec = MatroskaAudioCodec

    public let url: URL

    /// The Matroska track being decoded.
    public let track: MatroskaTrack

    /// The PCM format frames are decoded into — deinterleaved 32-bit float at the track's own rate,
    /// which is what the waveform and the audio engine both consume.
    public let processingFormat: AVAudioFormat

    /// The demuxed file's headers, so a caller reading PCM can still ask what it is reading.
    public var file: MatroskaFile { reader.file }

    /// Reopened rather than mutated when a file with no `Cues` index has to be rewound — hence
    /// `var`. See ``seek(toFrame:)``.
    private var reader: MatroskaFrameReader

    /// How this track's blocks become PCM. A compressed codec goes through Core Audio; a PCM track
    /// is already what the caller asked for and only needs its samples widened to float.
    private enum Path {
        case converter(AVAudioConverter, compressedFormat: AVAudioFormat)
        case pcm(MatroskaPCMBlockReader)
    }

    private let path: Path
    private var reachedEnd = false

    /// Packets handed to the converter, and frames it gave back, over the decoder's whole life.
    ///
    /// A stream description with the wrong packet length or source depth builds a converter that
    /// consumes packets, emits nothing, and reports success — so an empty result is only believable
    /// when there was nothing to decode. See ``endOfStream()``.
    private var suppliedPacketCount = 0
    private var producedFrameCount: AVAudioFramePosition = 0

    /// Decoder output not yet handed to a caller, and how far into it we have got. The decoder
    /// emits whatever a whole number of packets produced; callers ask for an exact frame count, so
    /// the remainder has to be held between calls.
    private var pending: AVAudioPCMBuffer?

    private var pendingOffset: AVAudioFrameCount = 0

    /// Where the current decode run began, in source frames, taken from the first packet's
    /// container timestamp. Nil until that packet is read — a run's origin is not knowable from the
    /// seek that started it, because the container restarts at the indexed boundary at or before
    /// what was asked for rather than at the request itself.
    private var runOriginFrame: AVAudioFramePosition?

    /// Frames of this run's output already consumed, counting the ones discarded to reach a seek
    /// target.
    private var runConsumedFrames: AVAudioFramePosition = 0

    /// Set by ``seek(toFrame:)`` and cleared once the run has been advanced to it.
    private var pendingSeekTarget: AVAudioFramePosition?

    /// The buffer to read from next, decoding another if the held one is spent. `nil` at the end.
    private func pendingBuffer() throws -> AVAudioPCMBuffer? {
        if let pending, pendingOffset < pending.frameLength {
            return pending
        }

        pending = try nextBuffer()
        pendingOffset = 0

        return pending
    }

    private func clearPending() {
        pending = nil
        pendingOffset = 0
        pcmRemainder = nil
    }

    // MARK: - Position

    /// The frame the next read will start at, in source frames.
    ///
    /// Derived rather than counted, so a seek and a sequential read cannot disagree about it: the
    /// container time this decode run began at, plus what the run has produced since.
    ///
    /// Defined over the buffered path — ``readNextChunk(into:frameCount:)`` and ``seek(toFrame:)``.
    /// ``nextBuffer(frameCapacity:)`` is the raw pull underneath both and does not move it, so a
    /// caller should use one or the other and not mix them.
    public var framePosition: AVAudioFramePosition {
        guard let runOriginFrame else {
            // Before the run's first packet there is nothing to derive from. A pending seek has
            // already stated where it is going, and a freshly opened file starts at zero.
            return pendingSeekTarget ?? 0
        }

        return runOriginFrame + runConsumedFrames
    }

    /// Advances the read position by up to `frameCount` frames, writing them into `buffer` when one
    /// is given and discarding them when it is not.
    ///
    /// One primitive for both, because reading and seeking differ only in whether the samples are
    /// kept — and two copies of this accounting is how a seek ends up off by a packet.
    ///
    /// - Returns: how many frames were consumed, short of `frameCount` only at the end of the track.
    @discardableResult
    func consume(
        frameCount: AVAudioFrameCount,
        into buffer: AVAudioPCMBuffer? = nil,
        at destinationOffset: AVAudioFrameCount = 0
    ) throws -> AVAudioFrameCount {
        var consumed: AVAudioFrameCount = 0

        while consumed < frameCount {
            guard let pending = try pendingBuffer() else { break }

            let taken = min(frameCount - consumed, pending.frameLength - pendingOffset)

            if let buffer {
                copy(
                    from: pending,
                    sourceOffset: pendingOffset,
                    to: buffer,
                    destinationOffset: destinationOffset + consumed,
                    frameCount: taken
                )
            }

            consumed += taken
            pendingOffset += taken
            runConsumedFrames += AVAudioFramePosition(taken)

            if pendingOffset >= pending.frameLength {
                clearPending()
            }
        }

        return consumed
    }

    /// Copies float samples between two buffers of the same format, channel by channel.
    private func copy(
        from source: AVAudioPCMBuffer,
        sourceOffset: AVAudioFrameCount,
        to destination: AVAudioPCMBuffer,
        destinationOffset: AVAudioFrameCount,
        frameCount: AVAudioFrameCount
    ) {
        guard frameCount > 0,
              let sourceData = source.floatChannelData,
              let destinationData = destination.floatChannelData
        else {
            return
        }

        let channelCount = Int(min(source.format.channelCount, destination.format.channelCount))

        for channel in 0 ..< channelCount {
            let from = sourceData[channel].advanced(by: Int(sourceOffset))
            let to = destinationData[channel].advanced(by: Int(destinationOffset))
            to.update(from: from, count: Int(frameCount))
        }
    }

    // MARK: - Seeking

    /// How far before a seek target the decode run is started.
    ///
    /// A block codec restarts with priming — samples it emits to fill its own state, which are not
    /// signal — so decoding straight from a boundary and keeping the first output is wrong. Landing
    /// early and discarding forward is the answer, and the discard needed to hit the target exactly
    /// already does that work; this only guarantees there is some to discard when the target lands
    /// on a boundary. Comfortably longer than AAC's 2112-frame priming at any rate decoded here.
    private static let seekPreroll: TimeInterval = 0.5

    /// Repositions so the next read starts at `frame`.
    ///
    /// A file with no `Cues` index still seeks, by decoding up to the target — see the fallback
    /// below. That costs time proportional to the distance, so it is O(1) on an indexed file and
    /// O(target) on one without.
    ///
    /// - Throws: ``MatroskaError`` if the container cannot be re-read at all.
    public func seek(toFrame frame: AVAudioFramePosition) throws {
        let target = max(0, frame)
        let targetTime = Double(target) / processingFormat.sampleRate

        do {
            try reader.seek(to: max(0, targetTime - Self.seekPreroll), trackNumber: track.number)

        } catch MatroskaError.noSeekIndex {
            // With no `Cues` there is nothing to look a position up in, so the only way to a
            // position is to decode up to it. **The cost is the distance, not the direction**:
            // forward continues from where the run already is, backward has to reopen and start
            // over, so a seek back to the top of a selection near the start of a file is nearly
            // free while one near the end of a long file is not.
            //
            // This deliberately does *not* refuse. A version that threw on any backward seek was
            // wrong on ordinary use, not just on scrubbing: pressing play with a selection seeks
            // back to its in-point, and so does playing the same file twice — both failed on every
            // indexless `.mkv`, which is most of them.
            guard target < framePosition else {
                // Already before the target, so the run can simply decode on to it — no restart,
                // and none of the state below needs clearing.
                try discardForward(to: target)
                return
            }

            // Reopened rather than rewound, because the walk holds a parsed position rather than an
            // offset. Falls through to the shared reset below.
            reader = try MatroskaFrameReader(url: url)
        }

        if case let .converter(converter, _) = path {
            converter.reset()
        }

        clearPending()

        reachedEnd = false
        runOriginFrame = nil
        runConsumedFrames = 0
        pendingSeekTarget = target

        try advanceToSeekTarget(target)
    }

    /// Decodes and discards from wherever the run restarted up to `target`.
    private func advanceToSeekTarget(_ target: AVAudioFramePosition) throws {
        defer { pendingSeekTarget = nil }

        // Establishes the run's origin as a side effect — the first packet is what states it.
        guard try pendingBuffer() != nil, runOriginFrame != nil else { return }

        try discardForward(to: target)
    }

    /// Decodes and throws away everything between the current position and `target`.
    ///
    /// Chunked because the distance is not always the preroll: an indexless forward seek discards
    /// the whole gap, and a day-long file overflows the 32-bit frame count in one call.
    private func discardForward(to target: AVAudioFramePosition) throws {
        var remaining = target - framePosition

        while remaining > 0 {
            let consumed = try consume(frameCount: AVAudioFrameCount(min(remaining, 1 << 20)))

            guard consumed > 0 else { return }

            remaining -= AVAudioFramePosition(consumed)
        }
    }

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

        guard let processingFormat = AVAudioFormat(
            standardFormatWithSampleRate: parameters.sampleRate,
            channels: AVAudioChannelCount(parameters.channelCount)
        ) else {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        self.processingFormat = processingFormat

        if codec.pcmSampleFormat != nil {
            guard let blockReader = MatroskaPCMBlockReader(track: track) else {
                throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
            }

            path = .pcm(blockReader)
            return
        }

        // The description comes from `spfk-matroska` rather than being rebuilt here: FLAC's packet
        // length and source depth are read from the file, and a second copy of that reading is how
        // one path decodes and the other returns silence.
        let formatDescription: CMAudioFormatDescription

        do {
            formatDescription = try track.makeAudioFormatDescription()
        } catch {
            throw MatroskaAudioDecoderError.unsupportedCodec(track.codecID)
        }

        let compressedFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        guard let converter = AVAudioConverter(from: compressedFormat, to: processingFormat) else {
            throw MatroskaAudioDecoderError.decoderUnavailable(track.codecID)
        }

        path = .converter(converter, compressedFormat: compressedFormat)
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

        guard case let .converter(converter, compressedFormat) = path else {
            return try nextPCMBuffer(into: output)
        }

        // `AVAudioConverter` calls the input block synchronously on this thread and is done with it
        // by the time `convert` returns -- nothing escapes and nothing runs concurrently. The block
        // is typed `@Sendable` regardless, which the compiler cannot reconcile with a decoder
        // holding a file position. `nonisolated(unsafe)` states that invariant, rather than
        // declaring the decoder `Sendable`, which it genuinely is not: two threads pulling from one
        // would interleave their reads of the same file.
        let source = self
        nonisolated(unsafe) var demuxError: (any Error)?

        let status = converter.convert(to: output, error: nil) { _, statusOut in
            do {
                guard let packet = try source.nextPacket(format: compressedFormat) else {
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

        producedFrameCount += AVAudioFramePosition(output.frameLength)

        switch status {
        case .endOfStream:
            try endOfStream()
            return output.frameLength > 0 ? output : nil

        case .error:
            throw MatroskaAudioDecoderError.decodeFailed(url)

        default:
            return output.frameLength > 0 ? output : nil
        }
    }

    /// Marks the track exhausted, refusing a run that decoded nothing out of packets that existed.
    ///
    /// Core Audio reports a stream description it cannot make sense of by consuming every packet
    /// and producing no audio, with no error at any point — so silence is the only symptom, and this
    /// is the only place it can be caught.
    private func endOfStream() throws {
        reachedEnd = true

        guard suppliedPacketCount > 0, producedFrameCount == 0 else { return }

        throw MatroskaAudioDecoderError.decodeFailed(url)
    }

    /// The next frame belonging to this track, skipping the interleaved video and subtitle frames
    /// the demuxer hands back alongside it.
    private func nextTrackFrame() throws -> MatroskaFrame? {
        while let frame = try reader.nextFrame() {
            guard frame.trackNumber == track.number, frame.data.isEmpty == false else {
                continue
            }

            // The first packet of a run is what states where the run begins: a seek asks for a
            // time and the container restarts at the indexed boundary at or before it, so the
            // request is not the answer.
            if runOriginFrame == nil {
                runOriginFrame = AVAudioFramePosition((frame.timestamp * processingFormat.sampleRate).rounded())
            }

            return frame
        }

        return nil
    }

    /// The next compressed packet for this track.
    private func nextPacket(format: AVAudioFormat) throws -> AVAudioCompressedBuffer? {
        guard let frame = try nextTrackFrame() else { return nil }

        let byteCount = frame.data.count

        let buffer = AVAudioCompressedBuffer(
            format: format,
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

        suppliedPacketCount += 1

        return buffer
    }

    // MARK: - PCM

    /// Bytes of a PCM block not yet emitted, and how many of its frames have been.
    ///
    /// A block holds whatever the muxer chose rather than a packet's worth, so it need not fit the
    /// buffer a caller asked for.
    private var pcmRemainder: (data: Data, consumedFrames: Int)?

    /// Fills `output` from the PCM blocks directly, converting samples to float as it goes.
    ///
    /// No `AVAudioConverter`: the container's payload is already linear PCM, and the only work is
    /// widening it to the processing format.
    private func nextPCMBuffer(into output: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        guard case let .pcm(blockReader) = path else { return nil }

        var written: AVAudioFrameCount = 0

        while written < output.frameCapacity {
            if pcmRemainder == nil {
                guard let frame = try nextTrackFrame() else {
                    try endOfStream()
                    break
                }

                suppliedPacketCount += 1
                pcmRemainder = (frame.data, 0)
            }

            guard let (data, consumedFrames) = pcmRemainder else { break }

            let available = data.count / blockReader.bytesPerFrame - consumedFrames

            guard available > 0 else {
                pcmRemainder = nil
                continue
            }

            let taken = min(Int(output.frameCapacity - written), available)

            blockReader.write(
                data,
                sourceFrameOffset: consumedFrames,
                to: output,
                destinationFrameOffset: Int(written),
                frameCount: taken
            )

            written += AVAudioFrameCount(taken)

            if consumedFrames + taken >= data.count / blockReader.bytesPerFrame {
                pcmRemainder = nil
            } else {
                pcmRemainder = (data, consumedFrames + taken)
            }
        }

        output.frameLength = written
        producedFrameCount += AVAudioFramePosition(written)

        return written > 0 ? output : nil
    }
}
