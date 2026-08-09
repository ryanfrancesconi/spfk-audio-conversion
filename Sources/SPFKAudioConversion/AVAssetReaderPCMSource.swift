// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKVideo

public enum AVAssetReaderPCMSourceError: LocalizedError {
    case noAudioTrack(URL)
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case let .noAudioTrack(url):
            "\(url.lastPathComponent) has no audio track"
        case let .unreadable(url):
            "\(url.lastPathComponent) could not be opened for reading"
        }
    }
}

/// Decodes **one named audio track** of an AVFoundation-readable file to PCM.
///
/// Exists because `AVAudioFile` cannot name a track: its initializers take a URL and nothing else,
/// and ExtAudioFile underneath offers no selection either — so the ordinary decode path always gets
/// whichever track the container lists first. A commentary or a dub is unreachable through it.
/// `AVAssetReader` can be pointed at a specific `AVAssetTrack`, which is the whole reason this type
/// exists alongside the simpler one.
///
/// The Matroska counterpart is `MatroskaAudioDecoder`, which answers the same protocols for a
/// container AVFoundation will not open at all. Between them every container this app reads can have
/// any of its audio tracks scanned or played.
///
/// `@unchecked Sendable` on the same terms as the Matroska decoder: this holds a position in a file,
/// so **one consumer may drive it and no more**. The conformance exists so a player can hand it to a
/// feed `Task`, and states that invariant rather than claiming thread safety.
public final class AVAssetReaderPCMSource: @unchecked Sendable {
    public let url: URL

    /// The track being decoded.
    public let track: AVAssetTrack

    /// Deinterleaved 32-bit float at the track's own rate — what the waveform scan and the audio
    /// engine both consume.
    public let processingFormat: AVAudioFormat

    private let asset: AVURLAsset

    /// Rebuilt on every seek: `AVAssetReader` cannot be repositioned, only re-created with a new
    /// `timeRange`. That is the same shape `MatroskaAudioDecoder` uses for an index-less file.
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?

    /// Decoder output not yet handed to a caller, and how far into it we have got. A reader emits
    /// whatever a sample buffer held; callers ask for an exact frame count.
    private var pending: AVAudioPCMBuffer?
    private var pendingOffset: AVAudioFrameCount = 0

    private var reachedEnd = false

    /// Where the next read starts, in frames of ``processingFormat``.
    public private(set) var framePosition: AVAudioFramePosition = 0

    private let frameCount: AVAudioFramePosition

    /// Opens `url` and prepares to decode one of its audio tracks.
    ///
    /// - Parameter audioTrack: which track, or `nil` for the first. An identifier the file does not
    ///   carry falls back to the first rather than throwing — a selection can outlive the file it
    ///   was made against.
    public init(url: URL, audioTrack: AudioTrackDescription.ID? = nil) async throws {
        self.url = url

        let asset = AVURLAsset(url: url)
        self.asset = asset

        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        let requested = audioTrack.flatMap { id in
            tracks.first { AudioTrackDescription.ID(persistentTrackID: $0.trackID) == id }
        }

        guard let track = requested ?? tracks.first else {
            throw AVAssetReaderPCMSourceError.noAudioTrack(url)
        }

        self.track = track

        // The track's own rate and channel count, so nothing is resampled on the way to a waveform.
        let descriptions = (try? await track.load(.formatDescriptions)) ?? []

        guard
            let description = descriptions.first,
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
            let processingFormat = AVAudioFormat(
                standardFormatWithSampleRate: streamDescription.mSampleRate,
                channels: AVAudioChannelCount(streamDescription.mChannelsPerFrame)
            )
        else {
            throw AVAssetReaderPCMSourceError.unreadable(url)
        }

        self.processingFormat = processingFormat

        let duration = (try? await track.load(.timeRange).duration) ?? .zero
        let seconds = CMTimeGetSeconds(duration)

        frameCount = seconds.isFinite && seconds > 0
            ? AVAudioFramePosition(seconds * processingFormat.sampleRate)
            : 0

        try startReading(atFrame: 0)
    }

    // MARK: - Reading

    /// Builds a reader positioned at `frame`.
    ///
    /// The output is asked for **interleaved** float, which is what `AVAssetReader` will produce
    /// without a second conversion; the deinterleave into the processing format happens per buffer.
    private func startReading(atFrame frame: AVAudioFramePosition) throws {
        reader?.cancelReading()

        let reader: AVAssetReader

        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AVAssetReaderPCMSourceError.unreadable(url)
        }

        if frame > 0 {
            let start = CMTime(
                value: CMTimeValue(frame),
                timescale: CMTimeScale(processingFormat.sampleRate)
            )
            reader.timeRange = CMTimeRange(start: start, duration: .positiveInfinity)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: processingFormat.sampleRate,
            AVNumberOfChannelsKey: Int(processingFormat.channelCount),
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AVAssetReaderPCMSourceError.unreadable(url)
        }

        reader.add(output)

        guard reader.startReading() else {
            throw AVAssetReaderPCMSourceError.unreadable(url)
        }

        self.reader = reader
        self.output = output

        pending = nil
        pendingOffset = 0
        reachedEnd = false
        framePosition = frame
    }

    /// The next decoded buffer, or `nil` at the end of the track.
    private func nextBuffer() throws -> AVAudioPCMBuffer? {
        guard reachedEnd == false, let reader, let output else { return nil }

        while true {
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                if reader.status == .failed {
                    throw reader.error ?? AVAssetReaderPCMSourceError.unreadable(url)
                }

                reachedEnd = true
                return nil
            }

            guard let buffer = Self.pcmBuffer(from: sampleBuffer, format: processingFormat),
                  buffer.frameLength > 0
            else {
                // An empty or undescribable buffer is not the end — keep pulling.
                continue
            }

            return buffer
        }
    }

    /// Deinterleaves one sample buffer into the processing format.
    private static func pcmBuffer(
        from sampleBuffer: CMSampleBuffer,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)

        guard frameCount > 0,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channelData = buffer.floatChannelData
        else {
            return nil
        }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        ) == noErr, let dataPointer else {
            return nil
        }

        let channelCount = Int(format.channelCount)

        dataPointer.withMemoryRebound(to: Float.self, capacity: frameCount * channelCount) { source in
            for channel in 0 ..< channelCount {
                for frame in 0 ..< frameCount {
                    channelData[channel][frame] = source[frame * channelCount + channel]
                }
            }
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        return buffer
    }

    /// The buffer to read from next, decoding another once the held one is spent.
    private func pendingBuffer() throws -> AVAudioPCMBuffer? {
        if let pending, pendingOffset < pending.frameLength {
            return pending
        }

        pending = try nextBuffer()
        pendingOffset = 0

        return pending
    }

    /// Copies up to `frameCount` frames into `buffer`, buffering whatever the reader over-produced.
    private func consume(
        frameCount: AVAudioFrameCount,
        into destination: AVAudioPCMBuffer
    ) throws -> AVAudioFrameCount {
        guard let destinationData = destination.floatChannelData else { return 0 }

        let channelCount = Int(processingFormat.channelCount)
        var written: AVAudioFrameCount = 0

        while written < frameCount {
            guard let source = try pendingBuffer(), let sourceData = source.floatChannelData else {
                break
            }

            let available = source.frameLength - pendingOffset
            let take = min(available, frameCount - written)

            guard take > 0 else { break }

            for channel in 0 ..< channelCount {
                let from = sourceData[channel] + Int(pendingOffset)
                let to = destinationData[channel] + Int(written)
                to.update(from: from, count: Int(take))
            }

            pendingOffset += take
            written += take
        }

        framePosition += AVAudioFramePosition(written)

        return written
    }
}

// MARK: - SeekablePCMSource

extension AVAssetReaderPCMSource: SeekablePCMSource {
    /// The track's own length. Reported from its time range rather than the asset's, which a longer
    /// sibling video track would overstate.
    public var totalFrameCount: AVAudioFramePosition { frameCount }

    public func readNextChunk(
        into buffer: AVAudioPCMBuffer,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioFrameCount {
        buffer.frameLength = 0

        let written = try consume(frameCount: frameCount, into: buffer)

        buffer.frameLength = written

        return written
    }

    /// Repositions by rebuilding the reader, then discarding the difference.
    ///
    /// **Landing exactly is the contract**, and `AVAssetReader.timeRange` does not honor it for a
    /// compressed track: it starts at the packet boundary at or before the requested time. So the
    /// reader is built slightly early and the surplus decoded and thrown away, which is what
    /// `MatroskaAudioDecoder` does for the same reason.
    public func seek(toFrame frame: AVAudioFramePosition) throws {
        let target = max(0, frame)

        let preroll = AVAudioFramePosition(processingFormat.sampleRate * Self.seekPrerollSeconds)
        let restart = max(0, target - preroll)

        try startReading(atFrame: restart)

        var remaining = target - restart

        while remaining > 0 {
            guard let source = try pendingBuffer() else { break }

            let available = AVAudioFramePosition(source.frameLength - pendingOffset)
            let skip = min(available, remaining)

            pendingOffset += AVAudioFrameCount(skip)
            remaining -= skip
        }

        framePosition = target
    }

    /// Enough to cover a packet boundary on every codec here, and cheap enough that a scrub does not
    /// notice it.
    private static var seekPrerollSeconds: Double { 0.5 }
}
