// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKUtils
import SPFKVideo

extension AudioFormatConverter {
    /// Frames requested per read while writing an intermediate.
    static let intermediateChunkFrames: AVAudioFrameCount = 16384

    /// Converts by decoding `pcmSource` to an intermediate WAV and running the ordinary pipeline
    /// on that.
    ///
    /// The route for anything ``start()``'s own branches cannot read: a container neither Core Audio
    /// nor AVFoundation opens, and an audio track neither will address.
    ///
    /// Metadata is copied from the original rather than the intermediate, which carries none.
    func convertViaIntermediate(
        pcmSource: some WaveformPCMSource,
        sampleFormat: (bitDepth: Int, isFloat: Bool)
    ) async throws {
        let intermediate = try writeIntermediateWAV(
            from: pcmSource,
            sampleFormat: sampleFormat,
            directory: source.output.deletingLastPathComponent()
        )

        defer {
            Log.debug("Removing intermediate file at", intermediate.path)
            try? intermediate.delete()
        }

        var innerSource = source
        innerSource.input = intermediate
        innerSource.metadataCopyScheme = .ignore
        // The intermediate holds the decoded track and nothing else.
        innerSource.audioTrack = nil

        let converter = AudioFormatConverter(source: innerSource)
        try await converter.start()

        // `start()` resolves a `.unique` output conflict and records the options the format could
        // not honor, both on its own copy of the source. A caller reading either off this converter
        // gets the intermediate run's answer only if they are carried back.
        source.output = await converter.source.output
        source.adjustments = await converter.source.adjustments

        await copyMetadata()
    }

    /// Writes everything `pcmSource` decodes into a WAV in `directory`.
    private func writeIntermediateWAV(
        from pcmSource: some WaveformPCMSource,
        sampleFormat: (bitDepth: Int, isFloat: Bool),
        directory: URL
    ) throws -> URL {
        let name = source.input.deletingPathExtension().lastPathComponent + "_" + Entropy.uniqueId + ".wav"
        let output = directory.appending(component: name, directoryHint: .notDirectory)

        let processingFormat = pcmSource.processingFormat

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: processingFormat.sampleRate,
            AVNumberOfChannelsKey: processingFormat.channelCount,
            AVLinearPCMBitDepthKey: sampleFormat.bitDepth,
            AVLinearPCMIsFloatKey: sampleFormat.isFloat,
            AVLinearPCMIsBigEndianKey: false,
        ]

        // A source hands back deinterleaved float32 whatever the track's own depth is — that is
        // what `commonFormat` and `interleaved` describe. `settings` describes the file on disk.
        var file: AVAudioFile? = try AVAudioFile(
            forWriting: output,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: Self.intermediateChunkFrames
        ) else {
            file = nil
            try? output.delete()
            throw NSError(description: "Unable to allocate a decode buffer for \(source.input.lastPathComponent)")
        }

        var writtenFrames: AVAudioFramePosition = 0

        do {
            while true {
                try Task.checkCancellation()

                let read = try pcmSource.readNextChunk(into: buffer, frameCount: Self.intermediateChunkFrames)
                guard read > 0 else { break }

                try file?.write(from: buffer)
                writtenFrames += AVAudioFramePosition(read)
            }
        } catch {
            file = nil
            try? output.delete()
            throw error
        }

        // Released here rather than at scope exit: a RIFF header states its chunk sizes, and they
        // are written when the file object goes away.
        file = nil

        guard writtenFrames > 0 else {
            try? output.delete()
            throw NSError(description: "No audio could be decoded from \(source.input.lastPathComponent)")
        }

        return output
    }
}

// MARK: - Track selection

extension AudioFormatConverter {
    /// Whether ``AudioFormatConverterSource/audioTrack`` names a track the ordinary decode path
    /// cannot reach.
    ///
    /// `AVAudioFile` and `ExtAudioFile` below it take the container's first audio track and offer no
    /// selection, so only a request for a different one needs decoding here. A selection the file
    /// does not carry falls back to the first, as it does everywhere else.
    func requiresTrackDemux() async -> Bool {
        guard let audioTrack = source.audioTrack else { return false }

        let tracks = (try? await source.asset.loadTracks(withMediaType: .audio)) ?? []

        guard let first = tracks.first,
              AudioTrackDescription.ID(persistentTrackID: first.trackID) != audioTrack
        else {
            return false
        }

        return tracks.contains { AudioTrackDescription.ID(persistentTrackID: $0.trackID) == audioTrack }
    }

    /// Converts the selected audio track of an AVFoundation-readable container.
    func convertSelectedAudioTrack() async throws {
        try Task.checkCancellation()

        let reader = try await AVAssetReaderPCMSource(url: source.input, audioTrack: source.audioTrack)

        // A track reached this way is a dub or a commentary, which is lossy in every file seen;
        // 24-bit is what the Matroska path writes for a codec that states no depth of its own.
        try await convertViaIntermediate(pcmSource: reader, sampleFormat: (24, false))
    }
}
