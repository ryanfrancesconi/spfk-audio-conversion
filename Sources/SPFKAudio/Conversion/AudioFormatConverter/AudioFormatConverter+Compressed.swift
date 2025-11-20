// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKMetadata
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
            throw NSError(description: "Unable to determine a compatible file type from \(source.input.lastPathComponent) for \(presetName)")
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
        var inputURL = source.input

        let inputFormat = AudioFileType(pathExtension: inputURL.pathExtension)

        let supportedInput = inputFormat == .wav ||
            inputFormat == .aiff ||
            inputFormat == .mp3

        let supportedChannels = (source.asset.audioFormat?.channelCount ?? 0) <= 2

        var tempFile: URL?

        // sox has limited input compatibility, so convert to wave if needed
        if !supportedInput || !supportedChannels {
            let temp = try await createTempFile(inputURL: inputURL, in: source.output.deletingLastPathComponent())

            if temp.exists {
                inputURL = temp
                tempFile = temp
            }
        }

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

        await SoX.shared.convertMP3(
            input: inputURL,
            output: outputURL,
            bitRate: options.bitRate / 1000, // sox bit rate is kbps
            sampleRate: options.sampleRate
        )

        guard outputURL.exists else {
            throw NSError(description: "Failed to convert to MP3: \(inputURL.lastPathComponent)")
        }
    }

    /// Convert to compressed first creating a tmp file to PCM to allow more flexible conversion
    /// options to work.
    func convertCompressed() async throws {
        if source.options.format == .mp3 {
            try await convertToMP3()
            return
        }

        let inputURL = source.input
        let outputURL = source.output

        let tempName = outputURL.deletingPathExtension().lastPathComponent + "_TEMP.wav"
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

        source.input = tempFile

        try await self.convertPCMToCompressed()
    }

    /// The AVFoundation way. *This doesn't currently handle compressed input - only compressed output.*
    func convertPCMToCompressed() async throws {
        guard let outputFormat = source.options.format else {
            throw NSError(description: "Options format can't be nil.")
        }

        // verify outputFormat
        guard AudioFormatConverter.outputFormats.contains(outputFormat) else {
            throw NSError(description: "The output file format isn't able to be produced by this class.")
        }

        self.reader = try AVAssetReader(asset: source.asset)

        guard let reader else {
            throw NSError(description: "Unable to setup the AVAssetReader.")
        }

        guard let inputFormat = source.asset.audioFormat else {
            throw NSError(description: "Unable to read the input file format.")
        }

        switch outputFormat {
        case .m4a, .mp4, .aiff, .caf, .wav:
            break
        default:
            throw NSError(description: "Unsupported output format: \(outputFormat)")
        }

        guard let format = outputFormat.avFileType,
              let formatKey = outputFormat.audioFormatID else {
            throw NSError(description: "Unsupported output format: \(outputFormat)")
        }

        self.writer = try AVAssetWriter(outputURL: source.output, fileType: format)

        guard let writer else {
            throw NSError(description: "Unable to setup the AVAssetWriter.")
        }

        // 1. chosen option. 2. same as input file. 3. 16 bit
        // optional in case of compressed audio. That said, the other conversion methods are actually used in
        // that case
        let bitDepth = (source.options.bitsPerChannel ?? inputFormat.settings[AVLinearPCMBitDepthKey] ?? 16) as Any

        var isFloat = false

        if let intDepth = bitDepth as? Int {
            isFloat = intDepth >= 32
        }

        var sampleRate = source.options.sampleRate ?? inputFormat.sampleRate
        let channels = source.options.channels ?? inputFormat.channelCount

        if sampleRate == 0 {
            Log.error("Sample rate can't be 0 - assigning to default format of 48k. inputFormat is", inputFormat)
            sampleRate = 48000
        }
        var outputSettings: [String: Any]?

        // Note: AVAssetReaderOutput does not currently support compressed audio
        if formatKey == kAudioFormatMPEG4AAC {
            if sampleRate > 48000 {
                sampleRate = 48000
            }
            // mono should be 1/2 the shown bitrate
            let perChannel = channels == 1 ? 2 : 1

            // reset these for m4a:
            outputSettings = [
                AVFormatIDKey: formatKey,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: Int(source.options.bitRate) / perChannel,
                AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
            ]
        } else {
            outputSettings = [
                AVFormatIDKey: formatKey,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: bitDepth,
                AVLinearPCMIsFloatKey: isFloat,
                AVLinearPCMIsBigEndianKey: format != .wav,
                AVLinearPCMIsNonInterleaved: !(source.options.isInterleaved ?? inputFormat.isInterleaved),
            ]
        }

        let hint = source.asset.audioFormat?.formatDescription

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings, sourceFormatHint: hint)

        writer.add(writerInput)

        guard let track = source.asset.tracks(withMediaType: .audio).first else {
            throw NSError(description: "No audio was found in the input file.")
        }

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)

        guard reader.canAdd(readerOutput) else {
            throw NSError(description: "Unable to add reader output.")
        }

        reader.add(readerOutput)

        if !writer.startWriting() {
            throw writer.error ?? NSError(description: "Failed to start writing")
        }

        writer.startSession(atSourceTime: .zero)

        if !reader.startReading() {
            throw reader.error ?? NSError(description: "Failed to start reading")
        }

        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else { return }

            self.write(reader: reader, readerOutput: readerOutput, writer: writer, writerInput: writerInput) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        await writer.finishWriting()
    }

    private func write(
        reader: AVAssetReader,
        readerOutput: AVAssetReaderOutput,
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let queue = DispatchQueue(label: "com.spongefork.AudioFormatConverter")

        var error: Error?

        // session.progress could be sent out via a delegate for this session
        writerInput.requestMediaDataWhenReady(
            on: queue,
            using: {
                var processing = true // safety flag to prevent runaway loops if errors

                while writerInput.isReadyForMoreMediaData, processing {
                    if reader.status == .reading, let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)

                    } else {
                        writerInput.markAsFinished()

                        switch reader.status {
                        case .failed:
                            writer.cancelWriting()
                            error = reader.error ?? NSError(description: "Conversion failed with error")

                        case .cancelled:
                            Log.error("Conversion cancelled")
                            error = NSError(description: "Conversion cancelled")

                        case .completed:
                            break

                        default:
                            break
                        }

                        completionHandler(error)
                        processing = false
                        break
                    }
                }
            }
        )
    }
}
