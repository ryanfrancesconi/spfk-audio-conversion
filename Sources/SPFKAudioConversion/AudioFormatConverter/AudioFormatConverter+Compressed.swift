// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKAudioConverterC
import SPFKBase
import SPFKUtils

extension AudioFormatConverter {
    /// Example of the most simplistic AVFoundation conversion.
    /// With this approach you can't really specify any settings other than the limited presets.
    /// No sample rate conversion in this. This isn't used in the public methods but is here
    /// for example.
    ///
    /// see `AVAssetExportSession`:
    /// *Prior to initializing an instance of AVAssetExportSession, you can invoke
    /// +allExportPresets to obtain the complete list of presets available. Use
    /// +exportPresetsCompatibleWithAsset: to obtain a list of presets that are compatible
    /// with a specific AVAsset.*

    public func convert(with presetName: String) async throws -> URL {
        guard let session = AVAssetExportSession(asset: source.asset, presetName: presetName) else {
            throw NSError(description: "Failed to create export session")
        }

        let list = await session.compatibleFileTypes

        guard let outputFileType: AVFileType = list.first else {
            throw NSError(
                description:
                "Unable to determine a compatible file type from \(source.input.lastPathComponent) for \(presetName)"
            )
        }

        session.outputURL = source.output
        session.outputFileType = outputFileType

        await session.export()

        return source.output
    }
}

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
    static let directConversionFormats: Set<AudioFileType> = [.mp3, .flac, .ogg]

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
        let status = converter.convert(
            toMP3: inputURL.path,
            output: source.output.path,
            bitRate: Int32(source.options.bitRate / 1000),
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

    // MARK: - OGG Conversion (libsndfile)

    /// Convert to OGG Opus using libsndfile directly.
    func convertToOGG() async throws {
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
        let status = converter.convert(
            toOGG: inputURL.path,
            output: source.output.path
        )

        guard status == 0, source.output.exists else {
            throw NSError(description: "Failed to convert to OGG: \(source.input.lastPathComponent)")
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
        // since libsndfile doesn't do resampling
        let needsResample: Bool
        if let targetRate = source.options.sampleRate {
            let sourceRate = audioFile?.fileFormat.sampleRate ?? 0
            needsResample = targetRate != sourceRate
        } else {
            needsResample = false
        }

        if supportedInput && supportedChannels && !needsResample {
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
            try await convertToOGG()
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
