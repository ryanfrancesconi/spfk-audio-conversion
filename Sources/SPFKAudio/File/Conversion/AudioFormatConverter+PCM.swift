// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKUtils

// MARK: - internal helper functions

public extension AudioFormatConverter {
    func convertToPCM(completionHandler: Callback? = nil) {
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

        guard outputFormat == .aiff || outputFormat == .wav || outputFormat == .caf,
              var format = outputFormat.audioFileTypeID else {
            completionHandler?(Self.createError(message: "Output file must be caf, wav or aif but it is \(outputFormat)"))
            return
        }

        // This might want to be an option or throw an error
        if format != kAudioFileCAFType,
           let fileSize = inputURL.regularFileAllocatedSize {
            let gb = fileSize / ByteCount.gigabyte.rawValue

            if gb >= 2 {
                Log.error("The input file is 2GB or greater so the format is being set to CAF (64 bit)")
                format = kAudioFileCAFType
            }
        }

        var inputFile: ExtAudioFileRef?
        var outputFile: ExtAudioFileRef?
        var err: OSStatus = noErr

        func closeFiles() {
            if let strongFile = inputFile {
                if noErr != ExtAudioFileDispose(strongFile) {
                    Log.error("Error disposing input file, could have a memory leak")
                }
            }
            inputFile = nil

            if let strongFile = outputFile {
                if noErr != ExtAudioFileDispose(strongFile) {
                    Log.error("Error disposing output file, could have a memory leak")
                }
            }
            outputFile = nil
        }

        // make sure these are closed on any exit to avoid leaking the file objects
        defer {
            closeFiles()
        }

        if noErr != ExtAudioFileOpenURL(inputURL as CFURL, &inputFile) {
            completionHandler?(Self.createError(message: "Unable to open the input file."))
            return
        }

        guard let strongInputFile = inputFile else {
            completionHandler?(Self.createError(message: "Unable to open the input file."))
            return
        }

        var inputDescription = AudioStreamBasicDescription()
        var inputDescriptionSize = UInt32(MemoryLayout.stride(ofValue: inputDescription))

        if noErr != ExtAudioFileGetProperty(strongInputFile,
                                            kExtAudioFileProperty_FileDataFormat,
                                            &inputDescriptionSize,
                                            &inputDescription) {
            completionHandler?(Self.createError(message: "Unable to get the input file data format."))
            return
        }

        var outputDescription = AudioFormatConverter.createOutputDescription(options: options,
                                                                             outputFormatID: format,
                                                                             inputDescription: inputDescription)

        let inputFormat = inputURL.pathExtension.lowercased()

        guard inputFormat != outputFormat.pathExtension ||
            outputDescription.mSampleRate != inputDescription.mSampleRate ||
            outputDescription.mChannelsPerFrame != inputDescription.mChannelsPerFrame ||
            outputDescription.mBitsPerChannel != inputDescription.mBitsPerChannel else {
            Log.error("No conversion is needed, formats are the same. Copying to", outputURL)
            // just copy it?
            do {
                try FileManager.default.copyItem(at: inputURL, to: outputURL)
                completionHandler?(nil)

            } catch {
                Log.error(error)
                completionHandler?(error)
            }
            return
        }

        // Create destination file
        err = ExtAudioFileCreateWithURL(outputURL as CFURL,
                                        format,
                                        &outputDescription,
                                        nil,
                                        AudioFileFlags.eraseFile.rawValue, // overwrite old file if present
                                        &outputFile)

        if err != noErr {
            let message = "Unable to create output file at \(outputURL.path). dstFormat \(outputDescription) Error: \(err.string) (\(err.fourCharCodeToString() ?? "?"))"
            completionProxy(error: Self.createError(message: message),
                            completionHandler: completionHandler)
            return
        }

        guard let strongOutputFile = outputFile else {
            completionProxy(error: Self.createError(message: "Output file is nil."),
                            completionHandler: completionHandler)
            return
        }

        // The format must be linear PCM (kAudioFormatLinearPCM).
        // You must set this in order to encode or decode a non-PCM file data format.
        // You may set this on PCM files to specify the data format used in your calls
        // to read/write.
        if noErr != ExtAudioFileSetProperty(strongInputFile,
                                            kExtAudioFileProperty_ClientDataFormat,
                                            inputDescriptionSize,
                                            &outputDescription) {
            completionProxy(error: Self.createError(message: "Unable to set data format on input file."),
                            completionHandler: completionHandler)
            return
        }

        if noErr != ExtAudioFileSetProperty(strongOutputFile,
                                            kExtAudioFileProperty_ClientDataFormat,
                                            inputDescriptionSize,
                                            &outputDescription) {
            completionProxy(error: Self.createError(message: "Unable to set the output file data format."),
                            completionHandler: completionHandler)
            return
        }
        let bufferByteSize: UInt32 = 32768
        var srcBuffer = [UInt8](repeating: 0, count: Int(bufferByteSize))
        var sourceFrameOffset: UInt32 = 0

        var error: Error?

        srcBuffer.withUnsafeMutableBytes { body in
            while true {
                let mBuffer = AudioBuffer(
                    mNumberChannels: inputDescription.mChannelsPerFrame,
                    mDataByteSize: bufferByteSize,
                    mData: body.baseAddress
                )

                var fillBufList = AudioBufferList(mNumberBuffers: 1,
                                                  mBuffers: mBuffer)
                var frameCount: UInt32 = 0

                if outputDescription.mBytesPerFrame > 0 {
                    frameCount = bufferByteSize / outputDescription.mBytesPerFrame
                }

                let readError = ExtAudioFileRead(strongInputFile,
                                                 &frameCount,
                                                 &fillBufList)
                if noErr != readError {
                    error = Self.createError(message: "Error reading from the input file.", code: Int(readError))
                    break
                }

                // EOF
                if frameCount == 0 {
                    break
                }

                sourceFrameOffset += frameCount

                let writeError = ExtAudioFileWrite(strongOutputFile,
                                                   frameCount,
                                                   &fillBufList)
                if noErr != writeError {
                    error = Self.createError(message: "Error writing to the output file.", code: Int(writeError))
                    break
                }
            }
        }

        Task { @MainActor [error] in
            if let error {
                Log.error(error.localizedDescription)

                self.completionProxy(
                    error: error,
                    completionHandler: completionHandler
                )
            } else {
                // no errors
                completionHandler?(nil)
            }
        }
    }

    static func createOutputDescription(options: AudioFormatConverterOptions,
                                        outputFormatID: AudioFormatID,
                                        inputDescription: AudioStreamBasicDescription) -> AudioStreamBasicDescription {
        let mFormatID: AudioFormatID = kAudioFormatLinearPCM

        let mSampleRate = options.sampleRate ?? inputDescription.mSampleRate
        let mChannelsPerFrame = options.channels ?? inputDescription.mChannelsPerFrame
        var mBitsPerChannel = options.bitsPerChannel ?? inputDescription.mBitsPerChannel

        // For example: don't allow upsampling to 24bit if the src is 16
        if options.bitDepthRule == .lessThanOrEqual && mBitsPerChannel > inputDescription.mBitsPerChannel {
            mBitsPerChannel = inputDescription.mBitsPerChannel
        }

        var mBytesPerFrame = mBitsPerChannel * mChannelsPerFrame / 8
        var mBytesPerPacket = options.bitsPerChannel == nil ? inputDescription.mBytesPerPacket : mBytesPerFrame

        if mBitsPerChannel == 0 {
            mBitsPerChannel = 16
            mBytesPerPacket = 2 * mChannelsPerFrame
            mBytesPerFrame = 2 * mChannelsPerFrame
        }

        var mFormatFlags: AudioFormatFlags = kLinearPCMFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger
        if outputFormatID == kAudioFileAIFFType {
            mFormatFlags = mFormatFlags | kLinearPCMFormatFlagIsBigEndian
        }

        if outputFormatID == kAudioFileWAVEType && mBitsPerChannel == 8 {
            // if is 8 BIT PER CHANNEL, remove kAudioFormatFlagIsSignedInteger
            mFormatFlags &= ~kAudioFormatFlagIsSignedInteger
        }

        return AudioStreamBasicDescription(mSampleRate: mSampleRate,
                                           mFormatID: mFormatID,
                                           mFormatFlags: mFormatFlags,
                                           mBytesPerPacket: mBytesPerPacket,
                                           mFramesPerPacket: 1,
                                           mBytesPerFrame: mBytesPerFrame,
                                           mChannelsPerFrame: mChannelsPerFrame,
                                           mBitsPerChannel: mBitsPerChannel,
                                           mReserved: 0)
    }
}
