import SPFKUtils
import AVFoundation

// MARK: - internal helper functions

public extension AudioFormatConverter {
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

    func convertCompressed(presetName: String) async throws -> URL {
        guard let inputURL = inputURL else {
            throw Self.createError(message: "Input file can't be nil.")
        }

        guard let outputURL = outputURL else {
            throw Self.createError(message: "Output file can't be nil.")
        }

        let asset = AVURLAsset(url: inputURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw NSError(description: "Failed to create export session")
        }

        let list = await session.compatibleFileTypes

        guard let outputFileType: AVFileType = list.first else {
            throw Self.createError(message: "Unable to determine a compatible file type from \(inputURL.path)")
        }

        session.outputURL = outputURL
        session.outputFileType = outputFileType

        await session.export()

        return outputURL
    }

    func convertToMP3(completionHandler: Callback? = nil) {
        guard var inputURL else {
            completionHandler?(Self.createError(message: "Input file can't be nil."))
            return
        }
        guard let outputURL else {
            completionHandler?(Self.createError(message: "Output file can't be nil."))
            return
        }

        guard let options else {
            completionHandler?(Self.createError(message: "Options can't be nil."))
            return
        }

        let inputExt = inputURL.pathExtension.lowercased()
        let supportedInput = inputExt.hasPrefix("wav") || inputExt.hasPrefix("aif") || inputExt.hasPrefix("mp3")

        var tempFile: URL?

        if !supportedInput {
            var tempOptions = AudioFormatConverterOptions()
            tempOptions.bitDepthRule = .lessThanOrEqual
            tempOptions.bitsPerChannel = 24
            tempOptions.sampleRate = options.sampleRate
            tempOptions.channels = options.channels
            tempOptions.format = AudioFileType.wav

            let tempName = outputURL.deletingPathExtension().lastPathComponent + "_" + Entropy.uniqueId + ".wav"
            let temp = outputURL.deletingLastPathComponent().appendingPathComponent(tempName)

            let tempConverter = AudioFormatConverter(inputURL: inputURL,
                                                     outputURL: temp,
                                                     options: tempOptions)

            tempConverter.convertToPCM()

            if temp.exists {
                inputURL = temp
                tempFile = temp
            }
        }

        processConvertToMP3(inputURL: inputURL,
                            outputURL: outputURL,
                            options: options,
                            completionHandler: completionHandler)

        if let tempFile = tempFile {
            Log.debug("Removing temp file at", tempFile.path)
            try? tempFile.delete()
        }
    }

    private func processConvertToMP3(inputURL: URL,
                                     outputURL: URL,
                                     options: AudioFormatConverterOptions,
                                     completionHandler: Callback? = nil) {
        // check input channels
        guard let avfile = try? AVAudioFile(forReading: inputURL) else {
            completionHandler?(Self.createError(message: "Failed to open input file: \(inputURL.lastPathComponent)"))
            return
        }

        guard avfile.fileFormat.channelCount <= 2 else {
            completionHandler?(Self.createError(message: "Incompatible number of channels for conversion: \(inputURL.lastPathComponent)"))
            return
        }

        SoxUtils.convertMP3(input: inputURL.path,
                            output: outputURL.path,
                            bitRate: options.bitRate / 1000, // sox bit rate is kbps
                            sampleRate: options.sampleRate)

        guard outputURL.exists else {
            completionHandler?(Self.createError(message: "Failed to convert to MP3: \(inputURL.lastPathComponent)"))
            return
        }

        completionHandler?(
            outputURL.exists ? nil : Self.createError(message: "Failed to convert to MP3: \(inputURL.lastPathComponent)")
        )
    }

    /// Convert to compressed first creating a tmp file to PCM to allow more flexible conversion
    /// options to work.
    func convertCompressed(completionHandler: Callback? = nil) {
        guard let inputURL = inputURL else {
            completionHandler?(Self.createError(message: "Input file can't be nil."))
            return
        }
        guard let outputURL = outputURL else {
            completionHandler?(Self.createError(message: "Output file can't be nil."))
            return
        }

        guard let options = options else {
            completionHandler?(Self.createError(message: "Options can't be nil."))
            return
        }

        if options.format == .mp3 {
            convertToMP3(completionHandler: completionHandler)
            return
        }

        let tempName = outputURL.deletingPathExtension().lastPathComponent + "_TEMP.wav"
        let tempFile = outputURL.deletingLastPathComponent().appendingPathComponent(tempName)

        var tempOptions = AudioFormatConverterOptions()
        tempOptions.bitDepthRule = .lessThanOrEqual
        tempOptions.bitsPerChannel = 24
        tempOptions.sampleRate = options.sampleRate
        tempOptions.channels = options.channels
        tempOptions.format = .wav

        let tempConverter = AudioFormatConverter(inputURL: inputURL,
                                                 outputURL: tempFile,
                                                 options: tempOptions)

        tempConverter.start { error in
            if let error = error {
                completionHandler?(Self.createError(message: "Failed to convert input to PCM: \(error.localizedDescription)"))
                return
            }

            self.inputURL = tempFile

            self.convertPCMToCompressed { error in
                try? FileManager.default.removeItem(at: tempFile)
                completionHandler?(error)
            }
        }
    }

    /// The AVFoundation way. *This doesn't currently handle compressed input - only compressed output.*
    func convertPCMToCompressed(completionHandler: Callback? = nil) {
        guard let inputURL else {
            completionHandler?(Self.createError(message: "Input file can't be nil."))
            return
        }
        guard let outputURL else {
            completionHandler?(Self.createError(message: "Output file can't be nil."))
            return
        }

        guard let options, let outputFormat = options.format else {
            completionHandler?(Self.createError(message: "Options can't be nil."))
            return
        }

        // verify outputFormat
        guard AudioFormatConverter.outputFormats.contains(outputFormat) else {
            completionHandler?(Self.createError(message: "The output file format isn't able to be produced by this class."))
            return
        }

        let asset = AVURLAsset(url: inputURL)
        do {
            self.reader = try AVAssetReader(asset: asset)

        } catch let err as NSError {
            completionHandler?(err)
            return
        }

        guard let reader = reader else {
            completionHandler?(Self.createError(message: "Unable to setup the AVAssetReader."))
            return
        }

        guard let inputFormat = asset.audioFormat else {
            completionHandler?(Self.createError(message: "Unable to read the input file format."))
            return
        }

        switch outputFormat {
        case .m4a, .mp4, .aiff, .caf, .wav:
            break
        default:
            Log.error("Unsupported output format: \(outputFormat)")
            return
        }

        guard let format = outputFormat.avFileType,
              let formatKey = outputFormat.audioFormatID else {
            Log.error("Unsupported output format: \(outputFormat)")
            return
        }

        do {
            self.writer = try AVAssetWriter(outputURL: outputURL, fileType: format)
        } catch let err as NSError {
            completionHandler?(err)
            return
        }

        guard let writer = writer else {
            completionHandler?(Self.createError(message: "Unable to setup the AVAssetWriter."))
            return
        }

        // 1. chosen option. 2. same as input file. 3. 16 bit
        // optional in case of compressed audio. That said, the other conversion methods are actually used in
        // that case
        let bitDepth = (options.bitsPerChannel ?? inputFormat.settings[AVLinearPCMBitDepthKey] ?? 16) as Any

        var isFloat = false

        if let intDepth = bitDepth as? Int {
            isFloat = intDepth >= 32
        }

        var sampleRate = options.sampleRate ?? inputFormat.sampleRate
        let channels = options.channels ?? inputFormat.channelCount

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
                AVEncoderBitRateKey: Int(options.bitRate) / perChannel,
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
                AVLinearPCMIsNonInterleaved: !(options.isInterleaved ?? inputFormat.isInterleaved),
            ]
        }

        let hint = asset.audioFormat?.formatDescription

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings, sourceFormatHint: hint)
        writer.add(writerInput)

        guard let track = asset.tracks(withMediaType: .audio).first else {
            completionProxy(error: Self.createError(message: "No audio was found in the input file."),
                            completionHandler: completionHandler)
            return
        }

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(readerOutput) else {
            completionProxy(error: Self.createError(message: "Unable to add reader output."),
                            completionHandler: completionHandler)
            return
        }
        reader.add(readerOutput)

        if !writer.startWriting() {
            Log.error("Failed to start writing. Error:", writer.error?.localizedDescription)
            completionProxy(error: writer.error,
                            completionHandler: completionHandler)
            return
        }

        writer.startSession(atSourceTime: .zero)

        if !reader.startReading() {
            Log.error("Failed to start reading. Error:", reader.error?.localizedDescription)
            completionProxy(error: reader.error,
                            completionHandler: completionHandler)
            return
        }

        let queue = DispatchQueue(label: "com.audiodesigndesk.ADD.FormatConverter.convertAsset")

        // session.progress could be sent out via a delegate for this session
        writerInput.requestMediaDataWhenReady(on: queue, using: {
            var processing = true // safety flag to prevent runaway loops if errors

            while writerInput.isReadyForMoreMediaData, processing {
                if reader.status == .reading,
                   let buffer = readerOutput.copyNextSampleBuffer() {
                    writerInput.append(buffer)

                } else {
                    writerInput.markAsFinished()

                    switch reader.status {
                    case .failed:
                        Log.error("Conversion failed with error", reader.error)
                        writer.cancelWriting()
                        self.completionProxy(error: reader.error, completionHandler: completionHandler)
                    case .cancelled:
                        Log.error("Conversion cancelled")
                        self.completionProxy(error: Self.createError(message: "Process cancelled"),
                                             completionHandler: completionHandler)
                    case .completed:
                        // writer.endSession(atSourceTime: asset.duration)
                        writer.finishWriting {
                            switch writer.status {
                            case .failed:
                                Log.error("Conversion failed at finishWriting")
                                self.completionProxy(error: writer.error,
                                                     completionHandler: completionHandler)
                            default:
                                // no errors
                                // Log.error("Conversion complete")
                                completionHandler?(nil)
                            }
                        }
                    default:
                        break
                    }
                    processing = false
                }
            }
        }) // requestMediaDataWhenReady
    }
}
