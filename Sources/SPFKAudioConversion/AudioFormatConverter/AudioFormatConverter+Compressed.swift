// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioBase
import SPFKSoX
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
        // let temp = source.output.deletingLastPathComponent().appendingPathComponent(tempName)
        let output = directory.appendingPathComponent(tempName)

        let tempConverter = AudioFormatConverter(
            inputURL: inputURL,
            outputURL: output,
            options: tempOptions
        )

        try await tempConverter.convertToPCM()

        return output
    }

    /// Using SoX for mp3 conversion
    func convertToMP3() async throws {
        try Task.checkCancellation()

        var inputURL = source.input

        let inputFormat = AudioFileType(pathExtension: inputURL.pathExtension)

        let supportedInput = inputFormat == .wav || inputFormat == .aiff || inputFormat == .mp3

        let asset = source.asset
        let supportedChannels = await (asset.audioFormat()?.channelCount ?? 0) <= 2

        var tempFile: URL?

        // sox has limited input compatibility, so convert to wave if needed
        if !supportedInput || !supportedChannels {
            let temp = try await createTempFile(inputURL: inputURL, in: source.output.deletingLastPathComponent())

            if temp.exists {
                inputURL = temp
                tempFile = temp
            }
        }

        try Task.checkCancellation()

        try await processConvertToMP3(
            inputURL: inputURL,
            outputURL: source.output,
            options: source.options
        )

        if let tempFile {
            Log.debug("Removing temp file at", tempFile.path)
            try? tempFile.delete()
        }
    }

    private func processConvertToMP3(
        inputURL: URL,
        outputURL: URL,
        options: AudioFormatConverterOptions
    ) async throws {
        // check input channels
        let avfile = try AVAudioFile(forReading: inputURL)

        guard avfile.fileFormat.channelCount <= 2 else {
            throw NSError(description: "Incompatible number of channels for conversion: \(inputURL.lastPathComponent)")
        }

        try await SoX.shared.convertMP3(
            input: inputURL,
            output: outputURL,
            bitRate: options.bitRate / 1000, // sox bit rate is kbps
            sampleRate: options.sampleRate
        )

        guard outputURL.exists else {
            throw NSError(description: "Failed to convert to MP3: \(inputURL.lastPathComponent)")
        }
    }

    /// Formats that are handled by SoX rather than AVAssetWriter.
    static let soxOutputFormats: Set<AudioFileType> = [.mp3, .flac, .ogg]

    /// Using SoX for FLAC conversion (lossless — uses bit depth, not bitrate).
    func convertToFLAC() async throws {
        try Task.checkCancellation()

        let inputURL = try await prepareSoXInput(source: source)

        defer {
            cleanUpTempFile(inputURL: inputURL, originalURL: source.input)
        }

        try Task.checkCancellation()

        try await SoX.shared.convertPCM(
            input: inputURL,
            output: source.output,
            bitDepth: source.options.bitsPerChannel,
            sampleRate: source.options.sampleRate
        )

        guard source.output.exists else {
            throw NSError(description: "Failed to convert to FLAC: \(source.input.lastPathComponent)")
        }
    }

    /// Using SoX for OGG Vorbis conversion (lossy — uses bitrate).
    func convertToOGG() async throws {
        try Task.checkCancellation()

        let inputURL = try await prepareSoXInput(source: source)

        defer {
            cleanUpTempFile(inputURL: inputURL, originalURL: source.input)
        }

        try Task.checkCancellation()

        let avfile = try AVAudioFile(forReading: inputURL)
        guard avfile.fileFormat.channelCount <= 2 else {
            throw NSError(description: "Incompatible number of channels for conversion: \(inputURL.lastPathComponent)")
        }

        try await SoX.shared.convertOGG(
            input: inputURL,
            output: source.output,
            bitRate: source.options.bitRate / 1000, // sox bit rate is kbps
            sampleRate: source.options.sampleRate
        )

        guard source.output.exists else {
            throw NSError(description: "Failed to convert to OGG: \(source.input.lastPathComponent)")
        }
    }

    /// Prepares a WAV input suitable for SoX if the original format is unsupported.
    /// Returns the original URL if already compatible, or a temp WAV file.
    private func prepareSoXInput(source: AudioFormatConverterSource) async throws -> URL {
        let inputFormat = AudioFileType(pathExtension: source.input.pathExtension)
        let supportedInput = inputFormat == .wav || inputFormat == .aiff || inputFormat == .flac

        let asset = source.asset
        let supportedChannels = await (asset.audioFormat()?.channelCount ?? 0) <= 2

        if supportedInput && supportedChannels {
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
