
import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata

extension AVAudioFile {
    /// the max level in the file as a Peak struct
    public var peak: Peak? {
        try? toAVAudioPCMBuffer().peak()
    }
}

extension AVAudioFile {
    public func normalize() throws {
        guard let buffer = try AVAudioPCMBuffer(url: self.url) else {
            throw NSError(description: "failed to read into buffer")
        }

        let normalized = try buffer.normalize()

        _ = try AVAudioFile(url: self.url, fromBuffer: normalized)
    }
}

extension AVAudioFile {
    /// - Returns: An extracted section of this file of the passed in conversion options
    public func extract(
        to url: URL,
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        fadeInTime: TimeInterval = 0,
        fadeOutTime: TimeInterval = 0,
        options: AudioFormatConverterOptions? = nil
    ) async throws {
        // if options are nil, create them to match the input file
        let options = options ?? AudioFormatConverterOptions(audioFile: self)

        guard let format = options?.format ?? AudioFileType(pathExtension: url.pathExtension) else {
            throw NSError(description: "Unable to determine format for \(url.path)")
        }

        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let tempFile = directory.appendingPathComponent(filename + "_temp").appendingPathExtension(AudioFileType.caf.rawValue)
        let outputURL = directory.appendingPathComponent(filename).appendingPathExtension(format.rawValue)

        // first print CAF file
        try extractToCAFFile(
            to: tempFile,
            from: startTime,
            to: endTime,
            fadeInTime: fadeInTime,
            fadeOutTime: fadeOutTime
        )

        // then convert to desired format here:
        guard tempFile.exists else {
            throw NSError(description: "CAF File wasn't created correctly")
        }

        // will be PCM
        try await AudioFormatConverter(inputURL: tempFile, outputURL: outputURL, options: options).start()

        do {
            // clean up temp file
            try FileManager.default.removeItem(at: tempFile)

        } catch {
            Log.error("Unable to remove temp file at", tempFile)
        }
    }

    /// Will return a 32bit CAF file
    @discardableResult public func extractToCAFFile(
        to outputURL: URL,
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        fadeInTime: TimeInterval = 0,
        fadeOutTime: TimeInterval = 0
    ) throws -> AVAudioFile {
        //
        let inputBuffer = try toAVAudioPCMBuffer()

        var editedBuffer = try inputBuffer.extract(from: startTime, to: endTime)

        if fadeInTime != 0 || fadeOutTime != 0 {
            editedBuffer = try editedBuffer.fade(inTime: fadeInTime, outTime: fadeOutTime)
        }

        var outputURL = outputURL

        if outputURL.pathExtension.lowercased() != "caf" {
            outputURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
        }

        return try AVAudioFile(url: outputURL, fromBuffer: editedBuffer)
    }
}
