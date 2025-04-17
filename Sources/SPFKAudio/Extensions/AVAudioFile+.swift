//  AVAudioFile+Extensions.swift
//  Created by Ryan Francesconi on 7/21/21.
//  Copyright © 2021 Audio Design Desk. All rights reserved.

import Accelerate
import AVFoundation
import SPFKUtils

extension AVAudioFile {
    /// Duration in seconds
    public var duration: TimeInterval {
        TimeInterval(length) / fileFormat.sampleRate
    }

    /// returns the max level in the file as a Peak struct
    public var peak: AVAudioPCMBuffer.Peak? {
        toAVAudioPCMBuffer()?.peak()
    }

    /// Convenience init to instantiate a file from an AVAudioPCMBuffer.
    public convenience init(url: URL, fromBuffer buffer: AVAudioPCMBuffer) throws {
        try self.init(forWriting: url, settings: buffer.format.settings)

        // Write the buffer in file
        do {
            framePosition = 0
            try write(from: buffer)
        } catch let error as NSError {
            Log.error(error)
            throw error
        }
    }

    /// converts to a 32 bit PCM buffer
    public func toAVAudioPCMBuffer() -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                            frameCapacity: AVAudioFrameCount(length)) else { return nil }

        do {
            framePosition = 0
            try read(into: buffer)

        } catch let error as NSError {
            Log.error("Cannot read into buffer " + error.localizedDescription)
        }

        return buffer
    }

    public func toAVAudioPCMBuffer(seconds: TimeInterval) -> AVAudioPCMBuffer? {
        guard seconds < duration else {
            return toAVAudioPCMBuffer()
        }

        let frameCapacity = AVAudioFrameCount(seconds * fileFormat.sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                            frameCapacity: frameCapacity) else { return nil }

        do {
            framePosition = 0
            try read(into: buffer, frameCount: frameCapacity)

        } catch let error as NSError {
            Log.error("Cannot read into buffer " + error.localizedDescription)
            return nil
        }

        return buffer
    }

    /// converts to Swift friendly Float array
    func toFloatChannelData() -> FloatChannelData? {
        guard let pcmBuffer = toAVAudioPCMBuffer(),
              let data = pcmBuffer.floatData else { return nil }
        return data
    }

    /// Will return a 32bit CAF file with the format of this buffer
    @discardableResult public func extract(to outputURL: URL,
                                           from startTime: TimeInterval,
                                           to endTime: TimeInterval,
                                           fadeInTime: TimeInterval = 0,
                                           fadeOutTime: TimeInterval = 0) throws -> AVAudioFile? {
        guard let inputBuffer = toAVAudioPCMBuffer() else {
            throw NSError(description: "Error reading into input buffer")
        }

        guard var editedBuffer = try inputBuffer.extract(from: startTime, to: endTime) else {
            throw NSError(description: "Failed to create edited buffer")
        }

        if fadeInTime != 0 || fadeOutTime != 0,
           let fadedBuffer = editedBuffer.fade(inTime: fadeInTime, outTime: fadeOutTime) {
            editedBuffer = fadedBuffer
        }

        var outputURL = outputURL
        if outputURL.pathExtension.lowercased() != "caf" {
            outputURL = outputURL.deletingPathExtension().appendingPathExtension("caf")
        }

        guard let outputFile = try? AVAudioFile(url: outputURL, fromBuffer: editedBuffer) else {
            throw NSError(description: "Failed to write new file at \(outputURL.path)")
        }
        return outputFile
    }

    /// - Returns: An extracted section of this file of the passed in conversion options
    public func extract(
        to url: URL,
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        fadeInTime: TimeInterval = 0,
        fadeOutTime: TimeInterval = 0,
        options: AudioFormatConverterOptions? = nil,
        completionHandler: AudioFormatConverter.Callback? = nil
    ) throws {
        func createError(message: String, code: Int = 1) -> NSError {
            let userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
            return NSError(domain: "FormatConverter.error", code: code, userInfo: userInfo)
        }

        // if options are nil, create them to match the input file
        let options = options ?? AudioFormatConverterOptions(audioFile: self)

        let format = options?.format ?? AudioFileType(pathExtension: url.pathExtension)
        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let tempFile = directory.appendingPathComponent(filename + "_temp").appendingPathExtension(AudioFileType.caf.rawValue)
        let outputURL = directory.appendingPathComponent(filename).appendingPathExtension(format.rawValue)

        // first print CAF file
        guard try extract(to: tempFile,
                          from: startTime,
                          to: endTime,
                          fadeInTime: fadeInTime,
                          fadeOutTime: fadeOutTime) != nil else {
            completionHandler?(createError(message: "Failed to create new file"))
            return
        }

        // then convert to desired format here:
        guard FileManager.default.isReadableFile(atPath: tempFile.path) else {
            completionHandler?(createError(message: "File wasn't created correctly"))
            return
        }

        let converter = AudioFormatConverter(inputURL: tempFile, outputURL: outputURL, options: options)
        converter.start { error in

            if let error = error {
                Log.error("Done, error", error)
            }

            completionHandler?(error)

            do {
                // clean up temp file
                try FileManager.default.removeItem(at: tempFile)
            } catch {
                Log.error("Unable to remove temp file at", tempFile)
            }
        }
    }
}
