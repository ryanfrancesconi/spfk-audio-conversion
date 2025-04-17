
import AVFoundation
import SPFKUtils

// MARK: - Definitions

extension AudioFormatConverter {
    /// Formats that this class can write
    public static let outputFormats: [AudioFileType] = [
        .wav, .aiff, .caf, .m4a, .mp3,
    ]

    public static let outputPathExtensions: [String] = outputFormats.map { $0.pathExtension }

    /// Formats that this class can read
    public static let inputFormats: [AudioFileType] = AudioFileType.allCases
}

public extension AudioFormatConverter {
    static func createError(message: String, code: Int = 1) -> NSError {
        let userInfo = [NSLocalizedDescriptionKey: message]
        return NSError(domain: "com.audiodesigndesk.FormatConverter.error",
                       code: code,
                       userInfo: userInfo)
    }
}

public extension AudioFormatConverter {
    /// Is this file a PCM file?
    /// - Parameters:
    ///   - url: The URL to parse
    ///   - ignorePathExtension: Do a deep parse rather than rely on the path extension
    /// - Returns: Bool or nil if it couldn't be determined
    static func isPCM(url: URL, ignorePathExtension: Bool = false) -> Bool? {
        guard let value = isCompressed(url: url) else { return nil }
        return !value
    }

    /// Compressed format or not
    static func isCompressed(url: URL, ignorePathExtension: Bool = false) -> Bool? {
        guard !ignorePathExtension else {
            return isCompressedExt(url: url)
        }
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "wav", "wave", "bwf", "aif", "aiff", "caf":
            return false

        case "m4a", "mp3", "mp4", "m4v", "mpg", "flac", "ogg":
            return true

        default:
            // if the file extension is missing or unknown, open the file and check it
            return isCompressedExt(url: url) ?? false
        }
    }

    private static func isCompressedExt(url: URL) -> Bool? {
        var inputFile: ExtAudioFileRef?

        func closeFiles() {
            if let strongFile = inputFile {
                // Log.error("🗑 Disposing input", inputURL.path)
                if noErr != ExtAudioFileDispose(strongFile) {
                    Log.error("Error disposing input file, could have a memory leak")
                }
            }
            inputFile = nil
        }

        // make sure these are closed on any exit
        defer {
            closeFiles()
        }

        if noErr != ExtAudioFileOpenURL(url as CFURL,
                                        &inputFile) {
            Log.error("Unable to open", url.lastPathComponent)
            return nil
        }

        guard let strongInputFile = inputFile else {
            return nil
        }

        var inputDescription = AudioStreamBasicDescription()
        var inputDescriptionSize = UInt32(MemoryLayout.stride(ofValue: inputDescription))

        if noErr != ExtAudioFileGetProperty(strongInputFile,
                                            kExtAudioFileProperty_FileDataFormat,
                                            &inputDescriptionSize,
                                            &inputDescription) {
        }

        let mFormatID = inputDescription.mFormatID

        switch mFormatID {
        case kAudioFormatLinearPCM,
             kAudioFormatAppleLossless: return false
        default:
            // basically all other format IDs are compressed
            return true
        }
    }
}

extension AudioFormatConverter {
    @discardableResult
    public static func convertToWave(
        inputURL: URL,
        outputURL: URL,
        sampleRate: Double?,
        bitDepth: UInt32 = 16
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            convertToWave(inputURL: inputURL, outputURL: outputURL, sampleRate: sampleRate) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: outputURL)
            }
        }
    }

    /// convenience function
    public static func convertToWave(
        inputURL: URL,
        outputURL: URL,
        sampleRate: Double?,
        bitDepth: UInt32 = 16,
        completionHandler: AudioFormatConverter.Callback?
    ) {
        var options = AudioFormatConverterOptions()
        options.bitsPerChannel = bitDepth
        options.sampleRate = sampleRate
        options.format = .wav

        Log.debug(options)

        let converter = AudioFormatConverter(
            inputURL: inputURL,
            outputURL: outputURL,
            options: options
        )

        converter.start(completionHandler: completionHandler)
    }
}
