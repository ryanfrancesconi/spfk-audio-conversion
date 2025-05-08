// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
import SPFKAudioC
import SPFKMetadata
import SPFKUtils

public class SoX {
    private let sox = SoxWrapper()

    // singleton as sox code is full of static variables currently
    static let shared = SoX()

    private init() {}

    // TODO: allow for trim fade time
    // doesn't accept 32bit files
    // needs error handling
    public func trim(
        input: URL,
        output: URL,
        timeChunk: TimeChunk
    ) -> Bool {
        trim(input: input, output: output, startTime: timeChunk.start, endTime: timeChunk.end)
    }

    public func trim(
        input: URL,
        output: URL,
        startTime: TimeInterval,
        endTime: TimeInterval = 0
    ) -> Bool {
        var endTimeStr: String = "0"

        if endTime > 0 {
            endTimeStr = "=" + String(endTime)
        }

        sox.trim(input.path, output: output.path, startTime: String(startTime), endTime: endTimeStr)

        return output.exists
    }

    public func convertPCM(input: URL, output: URL, bitDepth: UInt32?, sampleRate: Double?) {
        // Log.debug(input, "to:", output, bits, sampleRate)

        let inputPath = input.path
        let outputPath = output.path

        if let bitDepth, let sampleRate {
            sox.convert(inputPath, output: outputPath, bits: String(bitDepth), sampleRate: String(sampleRate))

        } else if let bitDepth {
            sox.convert(inputPath, output: outputPath, bits: String(bitDepth))

        } else if let sampleRate {
            sox.convert(inputPath, output: outputPath, sampleRate: String(sampleRate))

        } else {
            sox.convert(inputPath, output: outputPath)
        }
    }

    /**
     MP3 compressed audio; MP3 (MPEG Layer 3) is a part of the patent-encumbered MPEG standards for audio and video compression. It is a lossy compression format that achieves good compression rates with little quality loss.

     Because MP3 is patented, SoX cannot be distributed with MP3 support without incurring the patent holder’s fees. Users who require SoX with MP3 support must currently compile and build SoX with the MP3 libraries (LAME & MAD) from source code, or, in some cases, obtain pre-built dynamically loadable libraries.

     When reading MP3 files, up to 28 bits of precision is stored although only 16 bits is reported to user. This is to allow default behavior of writing 16 bit output files. A user can specify a higher precision for the output file to prevent lossing this extra information. MP3 output files will use up to 24 bits of precision while encoding.

     MP3 compression parameters can be selected using SoX’s −C option as follows (note that the current syntax is subject to change):

     The primary parameter to the LAME encoder is the bit rate. If the value of the −C value is a positive integer, it’s taken as the bitrate in kbps (e.g. if you specify 128, it uses 128 kbps).

     The second most important parameter is probably "quality" (really performance), which allows balancing encoding speed vs. quality. In LAME, 0 specifies highest quality but is very slow, while 9 selects poor quality, but is fast. (5 is the default and 2 is recommended as a good trade-off for high quality encodes.)

     Because the −C value is a float, the fractional part is used to select quality. 128.2 selects 128 kbps encoding with a quality of 2. There is one problem with this approach. We need 128 to specify 128 kbps encoding with default quality, so 0 means use default. Instead of 0 you have to use .01 (or .99) to specify the highest quality (128.01 or 128.99).

     LAME uses bitrate to specify a constant bitrate, but higher quality can be achieved using Variable Bit Rate (VBR). VBR quality (really size) is selected using a number from 0 to 9. Use a value of 0 for high quality, larger files, and 9 for smaller files of lower quality. 4 is the default.

     In order to squeeze the selection of VBR into the the −C value float we use negative numbers to select VRR. -4.2 would select default VBR encoding (size) with high quality (speed). One special case is 0, which is a valid VBR encoding parameter but not a valid bitrate. Compression value of 0 is always treated as a high quality vbr, as a result both -0.2 and 0.2 are treated as highest quality VBR (size) and high quality (speed).
     */
    public func convertMP3(
        input: URL,
        output: URL,
        bitRate: UInt32?,
        sampleRate: Double?
    ) {
        // Log.debug(input, "to:", output, bitRate, sampleRate)

        let inputPath = input.path
        let outputPath = output.path

        if let bitRate, let sampleRate {
            sox.convert(inputPath, output: outputPath, bitRate: String(bitRate) + ".2", sampleRate: String(sampleRate))

        } else if let bitRate {
            sox.convert(inputPath, output: outputPath, bitRate: String(bitRate) + ".2")

        } else if let sampleRate {
            sox.convert(inputPath, output: outputPath, sampleRate: String(sampleRate))

        } else {
            sox.convert(inputPath, output: outputPath)
        }
    }

    /// Split stereo files to dual mono
    ///        sox infile.wav outfile.L.wav remix 1
    ///        sox infile.wav outfile.R.wav remix 2
    public func exportSplitStereo(
        input source: URL,
        destination: URL? = nil,
        newName: String? = nil,
        overwrite: Bool = true
    ) throws -> SplitStereoPair {
        // check source input

        let audioFile = try AVAudioFile(forReading: source)

        guard audioFile.length > 0 && audioFile.duration > 0 else {
            Log.debug("length", audioFile.length, "duration", audioFile.duration, "channelCount", audioFile.fileFormat.channelCount)

            throw NSError(description: "duration is 0 for \(source.path)")
        }

        var outputBin = source.deletingLastPathComponent()

        if let destination = destination, destination.isDirectory {
            outputBin = destination
        }

        let baseName = newName ?? source.deletingPathExtension().lastPathComponent

        let left = baseName + ".L." + source.pathExtension
        let right = baseName + ".R." + source.pathExtension

        let url1 = outputBin.appendingPathComponent(left)
        let url2 = outputBin.appendingPathComponent(right)

        if overwrite || !url1.exists {
            sox.remix(source.path, output: url1.path, channel: "1")
        }

        if overwrite || url1.exists {
            sox.remix(source.path, output: url2.path, channel: "2")
        }

        guard url1.exists, url2.exists else {
            throw NSError(description: "Failed to convert stereo pair")
        }

        return SplitStereoPair(left: url1, right: url2)
    }

    /// Export all channels as mono files
    public func exportChannels(
        input source: URL,
        destination: URL? = nil,
        newName: String? = nil
    ) throws -> [URL] {
        var outputBin = source.deletingLastPathComponent()

        if let destination = destination, destination.isDirectory {
            outputBin = destination
        }

        let baseName = newName ?? source.deletingPathExtension().lastPathComponent

        let channels = try AVAudioFile(forReading: source).fileFormat.channelCount

        var urls = [URL]()

        for i in 0 ..< channels {
            let channel = i + 1
            let filename = baseName + ".\(channel)." + source.pathExtension
            let url = outputBin.appendingPathComponent(filename)

            // TODO: needs error handling
            sox.remix(source.path, output: url.path, channel: channel.string)

            urls.append(url)
        }

        return urls
    }

    /// Mix a stereo file to mono
    public func stereoToMono(
        source: URL,
        destination: URL? = nil,
        newName: String? = nil,
        overwrite: Bool = true
    ) -> URL? {
        var outputBin = source.deletingLastPathComponent()

        if let destination = destination, destination.isDirectory {
            outputBin = destination
        }

        let baseName = newName ?? source.deletingPathExtension().lastPathComponent
        let left = baseName + ".Mono." + source.pathExtension

        let url1 = outputBin.appendingPathComponent(left)

        sox.remix(source.path, output: url1.path, channel: "1")

        guard url1.exists else {
            // failed
            return nil
        }

        return url1
    }

    /// sox -M chan1.wav chan2.wav chan3.wav chan4.wav chan5.wav multi.wav
    public func createMultiChannelWave(
        input files: [URL],
        output: URL
    ) -> Bool {
        let inputs = files.filter {
            $0.exists
        }

        guard inputs.isNotEmpty else { return false }

        let paths = inputs.map { $0.path }

        sox.createMultiChannelWave(paths, output: output.path)

        return output.exists
    }
}
