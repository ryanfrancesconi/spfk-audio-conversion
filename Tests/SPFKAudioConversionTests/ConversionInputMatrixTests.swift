// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMatroska
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

/// Which containers the converter accepts as *input*, asserted per format.
///
/// The rest of the suite converts from `tabla.wav` almost exclusively, which is how the whole
/// Matroska family became unconvertible with every test green.
@Suite(.tags(.file), .serialized)
final class ConversionInputMatrixTests: BinTestCase {
    /// Every committed fixture that names a container the app lets a user import.
    static let inputs: [URL] = {
        let resources = TestBundleResources.shared

        return [
            resources.tabla_wav,
            resources.tabla_aif,
            resources.tabla_caf,
            resources.tabla_mp3,
            resources.tabla_m4a,
            resources.tabla_aac,
            resources.tabla_mp4,
            resources.tabla_flac,
            resources.tabla_ogg,
            resources.sample_mov,
            resources.tabla_mka,
            resources.tabla_flac_mka,
            resources.tabla_pcm_mka,
            resources.dualaudio_mka,
            resources.sample_mkv,
            resources.sample_webm,
        ]
    }()

    /// One target per route out of ``AudioFormatConverter/start()``: `ExtAudioFile` for `.wav`,
    /// `AVAssetWriter` for `.m4a`, libsndfile for `.flac`.
    static let outputs: [AudioFileType] = [.wav, .m4a, .flac]

    @Test(arguments: inputs, outputs)
    func convertsEveryAcceptedInput(input: URL, output: AudioFileType) async throws {
        let outputURL = bin.appending(
            component: "\(input.deletingPathExtension().lastPathComponent)-\(output.pathExtension)"
                + ".\(output.pathExtension)",
            directoryHint: .notDirectory
        )

        var options = AudioFormatConverterOptions()
        options.format = output

        try await AudioFormatConverter(inputURL: input, outputURL: outputURL, options: options).start()

        #expect(outputURL.exists)

        let file = try AVAudioFile(forReading: outputURL)

        // The fixtures are all 2 seconds or longer, so a shorter result means frames were dropped.
        // A wrong stream description decodes silence and reports success, which only a positive
        // frame count catches.
        let duration = Double(file.length) / file.processingFormat.sampleRate
        #expect(duration > 1, "\(input.lastPathComponent) → \(output.pathExtension) produced \(duration)s")
        #expect(file.processingFormat.channelCount > 0)
    }

    /// `sample.mkv` and `sample.webm` carry video, and the audio target is the wanted outcome
    /// rather than a fallback — nothing in the output should be video.
    @Test func convertsAVideoSourceToAudio() async throws {
        let outputURL = bin.appending(component: "sample-video-to-m4a.m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a

        try await AudioFormatConverter(
            inputURL: TestBundleResources.shared.sample_mkv,
            outputURL: outputURL,
            options: options
        ).start()

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        #expect(videoTracks.isEmpty)
        #expect(audioTracks.count == 1)
    }

    /// A codec that does not decode has to fail naming the *codec*. Every Matroska failure used to
    /// read `Unable to open the input file.`, which names neither the codec nor the container.
    @Test func refusesAnUndecodableCodecByName() async throws {
        let input = bin.appending(component: "undecodable.mka", directoryHint: .notDirectory)
        try retagCodec(of: TestBundleResources.shared.tabla_mka, as: "A_DTS", to: input)

        let outputURL = bin.appending(component: "undecodable.wav", directoryHint: .notDirectory)

        await #expect(throws: MatroskaAudioDecoderError.unsupportedCodec("A_DTS")) {
            try await AudioFormatConverter(inputURL: input, outputURL: outputURL).start()
        }

        #expect(MatroskaAudioDecoderError.unsupportedCodec("A_DTS").localizedDescription.contains("A_DTS"))
    }

    // MARK: - Track selection

    /// `dualaudio.mka` states a 440 Hz track and an 880 Hz track, so the frequency of the output
    /// names which one was converted. Both run 2.09 s, so duration discriminates nothing.
    @Test func convertsTheAudioTrackItWasAskedFor() async throws {
        let input = TestBundleResources.shared.dualaudio_mka
        let descriptions = try MatroskaFile(url: input).audioTrackDescriptions

        let english = try #require(descriptions.first { $0.language == "eng" })
        let japanese = try #require(descriptions.first { $0.language == "jpn" })

        var options = AudioFormatConverterOptions()
        options.format = .wav

        func convert(track: AudioTrackDescription.ID, named name: String) async throws -> Double {
            let outputURL = bin.appending(component: "\(name).wav", directoryHint: .notDirectory)

            var source = AudioFormatConverterSource(input: input, output: outputURL, options: options)
            source.audioTrack = track

            try await AudioFormatConverter(source: source).start()

            return try dominantFrequency(of: outputURL)
        }

        // Each measurement is held to the octave it belongs in rather than to a tolerance: 32 kbps
        // AAC puts the estimate several percent off either tone, and which track was converted is
        // what this asks.
        let englishFrequency = try await convert(track: english.id, named: "english")
        let japaneseFrequency = try await convert(track: japanese.id, named: "japanese")

        #expect(englishFrequency < 660, "english track measured \(englishFrequency) Hz, expected near 440")
        #expect(japaneseFrequency > 660, "japanese track measured \(japaneseFrequency) Hz, expected near 880")
    }

    /// A selection can outlive the file it was made against, so an unknown identifier converts the
    /// first track rather than failing.
    @Test func fallsBackToTheFirstTrackForAnUnknownIdentifier() async throws {
        let outputURL = bin.appending(component: "unknown-track.wav", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .wav

        var source = AudioFormatConverterSource(
            input: TestBundleResources.shared.dualaudio_mka,
            output: outputURL,
            options: options
        )
        source.audioTrack = AudioTrackDescription.ID(rawValue: 999_999)

        try await AudioFormatConverter(source: source).start()

        let frequency = try dominantFrequency(of: outputURL)
        #expect(frequency < 660, "measured \(frequency) Hz, expected the 440 Hz first track")
    }

    // MARK: - Helpers

    /// Cycles per second of the loudest tone in the first second, by zero crossing. Adequate only
    /// for the single-tone fixtures it is used on.
    private func dominantFrequency(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let wanted = AVAudioFrameCount(min(Double(file.length), format.sampleRate))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: wanted) else { return 0 }

        try file.read(into: buffer, frameCount: wanted)

        guard let data = buffer.floatChannelData, buffer.frameLength > 32 else { return 0 }

        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))

        let threshold: Float = 0.05
        var crossings = 0
        var lastSign = 0

        for sample in samples where abs(sample) > threshold {
            let sign = sample > 0 ? 1 : -1

            if lastSign != 0, sign != lastSign {
                crossings += 1
            }

            lastSign = sign
        }

        return Double(crossings) / 2 / (Double(buffer.frameLength) / format.sampleRate)
    }

    /// Writes a copy of `source` with its first `CodecID` overwritten, giving a container the
    /// decoder must refuse.
    ///
    /// A same-length replacement so no EBML element size changes and the file stays parseable —
    /// which is the point, since the refusal being tested is the codec's and not the container's.
    private func retagCodec(of source: URL, as codecID: String, to destination: URL) throws {
        var data = try Data(contentsOf: source)

        let replacement = try #require(codecID.data(using: .ascii))
        let existing = try #require("A_AAC".data(using: .ascii))

        #expect(replacement.count == existing.count)

        let range = try #require(data.range(of: existing))
        data.replaceSubrange(range, with: replacement)

        try data.write(to: destination)
    }
}
