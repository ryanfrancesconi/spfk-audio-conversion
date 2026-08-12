// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import SPFKAudioBase
import SPFKAudioConverterC
import SPFKBase
import SPFKUtils

// MARK: - internal helper functions

extension AudioFormatConverter {
    func createTempFile(inputURL: URL, in directory: URL) async throws -> URL {
        var tempOptions = AudioFormatConverterOptions()
        tempOptions.bitDepthRule = .lessThanOrEqual
        tempOptions.bitsPerChannel = 24
        tempOptions.sampleRate = source.options.sampleRate
        tempOptions.channels = source.options.channels ?? 2
        tempOptions.format = .wav

        let tempName = inputURL.deletingPathExtension().lastPathComponent + "_" + Entropy.uniqueId + ".wav"
        let output = directory.appendingPathComponent(tempName)

        let tempConverter = AudioFormatConverter(
            inputURL: inputURL,
            outputURL: output,
            options: tempOptions
        )

        try await tempConverter.convertToPCM()

        return output
    }

    /// Formats handled by direct library calls (libsndfile / LAME).
    static let directConversionFormats: Set<AudioFileType> = [.mp3, .flac, .ogg, .opus]

    // MARK: - MP3 Conversion (LAME)

    /// Convert to MP3 using LAME directly.
    func convertToMP3() async throws {
        try Task.checkCancellation()

        let inputURL = try await prepareInput(source: source)

        defer {
            cleanUpTempFile(inputURL: inputURL, originalURL: source.input)
        }

        try Task.checkCancellation()

        let avfile = try AVAudioFile(forReading: inputURL)
        guard avfile.fileFormat.channelCount <= 2 else {
            throw NSError(description: "Incompatible number of channels for conversion: \(inputURL.lastPathComponent)")
        }

        let converter = LameConverter()
        let bitRate = Int32(source.options.bitRate / 1000)

        let status = converter.convert(
            toMP3: inputURL.path,
            output: source.output.path,
            bitRate: bitRate,
            quality: 2
        )

        guard status == 0, source.output.exists else {
            throw NSError(description: "Failed to convert to MP3: \(source.input.lastPathComponent)")
        }
    }

    // MARK: - FLAC Conversion (libsndfile)

    /// Convert to FLAC using libsndfile directly (lossless — uses bit depth, not bitrate).
    func convertToFLAC() async throws {
        try Task.checkCancellation()

        let inputURL = try await prepareInput(source: source)

        defer {
            cleanUpTempFile(inputURL: inputURL, originalURL: source.input)
        }

        try Task.checkCancellation()

        let converter = SndFileConverter()
        let bitDepth = Int32(source.options.bitsPerChannel ?? 0)
        let status = converter.convert(
            toFLAC: inputURL.path,
            output: source.output.path,
            bitDepth: bitDepth
        )

        guard status == 0, source.output.exists else {
            throw NSError(description: "Failed to convert to FLAC: \(source.input.lastPathComponent)")
        }
    }

    // MARK: - Ogg Conversion (libsndfile)

    /// Convert to Ogg Vorbis using libsndfile directly.
    func convertToVorbis() async throws {
        try await convertToOgg(isOpus: false)
    }

    /// Convert to Ogg Opus using libsndfile directly.
    func convertToOpus() async throws {
        try await convertToOgg(isOpus: true)
    }

    private func convertToOgg(isOpus: Bool) async throws {
        try Task.checkCancellation()

        let inputURL = try await prepareInput(source: source)

        defer {
            cleanUpTempFile(inputURL: inputURL, originalURL: source.input)
        }

        try Task.checkCancellation()

        let avfile = try AVAudioFile(forReading: inputURL)
        guard avfile.fileFormat.channelCount <= 2 else {
            throw NSError(description: "Incompatible number of channels for conversion: \(inputURL.lastPathComponent)")
        }

        let converter = SndFileConverter()
        let status = isOpus
            ? converter.convert(toOpus: inputURL.path, output: source.output.path)
            : converter.convert(toVorbis: inputURL.path, output: source.output.path)

        guard status == 0, source.output.exists else {
            let codec = isOpus ? "Opus" : "Vorbis"
            throw NSError(description: "Failed to convert to Ogg \(codec): \(source.input.lastPathComponent)")
        }
    }

    // MARK: - Input Preparation

    /// Prepares a WAV input if the original format is unsupported by the target encoder.
    /// Returns the original URL if already compatible, or a temp WAV file.
    /// Sample rate conversion happens here via CoreAudio's ExtAudioFile.
    private func prepareInput(source: AudioFormatConverterSource) async throws -> URL {
        let inputFormat = AudioFileType(pathExtension: source.input.pathExtension)
        let supportedInput = inputFormat == .wav || inputFormat == .aiff || inputFormat == .flac

        // Check channel count and sample rate via AVAudioFile
        let audioFile = try? AVAudioFile(forReading: source.input)
        let channelCount = audioFile?.fileFormat.channelCount ?? 0
        let supportedChannels = channelCount <= 2

        // If sample rate conversion is requested, always create a temp file
        // since libsndfile doesn't do resampling.
        //
        // Opus encodes only at these rates. If the output is Opus and the source rate
        // isn't among them, force a resample to 48000 Hz so libsndfile doesn't reject
        // the input. Vorbis has no such restriction.
        let supportedOpusRates: Set<Double> = [8000, 12000, 16000, 24000, 48000]
        let sourceRate = audioFile?.fileFormat.sampleRate ?? 0
        let outputFormat = AudioFileType(pathExtension: source.output.pathExtension)

        let needsResample: Bool
        if let targetRate = source.options.sampleRate {
            if outputFormat == .opus, !supportedOpusRates.contains(targetRate) {
                // Opus cannot encode the requested rate. Snap to the nearest it supports,
                // otherwise libsndfile rejects the write — most of `supportedSampleRates`
                // is invalid for Opus.
                let nearest = supportedOpusRates.min {
                    abs($0 - targetRate) < abs($1 - targetRate)
                }
                self.source.options.sampleRate = nearest

                if let nearest {
                    self.source.adjustments.append(
                        .sampleRate(requested: targetRate, applied: nearest, format: .opus)
                    )
                }
            }
            needsResample = self.source.options.sampleRate != sourceRate
        } else if outputFormat == .opus, !supportedOpusRates.contains(sourceRate) {
            // No user-specified rate, but Opus can't handle this source rate.
            // Inject 48000 Hz so createTempFile resamples to a valid Opus rate.
            self.source.options.sampleRate = 48000
            self.source.adjustments.append(
                .sampleRate(requested: sourceRate, applied: 48000, format: .opus)
            )
            needsResample = true
        } else {
            needsResample = false
        }

        if supportedInput, supportedChannels, !needsResample {
            return source.input
        }

        let temp = try await createTempFile(
            inputURL: source.input,
            in: source.output.deletingLastPathComponent()
        )

        guard temp.exists else {
            return source.input
        }

        return temp
    }

    /// Removes temp file if it differs from the original.
    private func cleanUpTempFile(inputURL: URL, originalURL: URL) {
        guard inputURL != originalURL else { return }
        Log.debug("Removing temp file at", inputURL.path)
        try? inputURL.delete()
    }

    /// Convert to compressed first creating a tmp file to PCM to allow more flexible conversion
    /// options to work.
    func convertCompressed() async throws {
        try Task.checkCancellation()

        switch source.options.format {
        case .mp3:
            try await convertToMP3()
            return
        case .flac:
            try await convertToFLAC()
            return
        case .ogg:
            try await convertToVorbis()
            return
        case .opus:
            try await convertToOpus()
            return
        default:
            break
        }

        let inputURL = source.input
        let outputURL = source.output

        let tempName = outputURL.deletingPathExtension().lastPathComponent + "_tmp.wav"
        let tempFile = outputURL.deletingLastPathComponent().appendingPathComponent(tempName)

        var tempOptions = AudioFormatConverterOptions()
        tempOptions.bitDepthRule = .lessThanOrEqual
        tempOptions.bitsPerChannel = 24
        tempOptions.sampleRate = source.options.sampleRate
        tempOptions.channels = source.options.channels
        tempOptions.format = .wav

        let tempConverter = AudioFormatConverter(
            inputURL: inputURL,
            outputURL: tempFile,
            options: tempOptions
        )

        defer {
            Log.debug("Removing \(tempFile)")
            try? FileManager.default.removeItem(at: tempFile)
        }

        try await tempConverter.start()

        try Task.checkCancellation()

        var assetWriterSource = source
        assetWriterSource.input = tempFile

        try await AssetWriter(source: assetWriterSource).start()
    }
}
