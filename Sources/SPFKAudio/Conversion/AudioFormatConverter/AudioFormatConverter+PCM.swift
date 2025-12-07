// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKUtils

extension AudioFormatConverter {
    public func convertToPCM() async throws {
        guard let outputFormat = source.options.format else {
            throw NSError(description: "Options can't be nil.")
        }

        let inputURL = source.input
        let outputURL = source.output

        guard outputFormat == .aiff || outputFormat == .wav || outputFormat == .caf,
              var format = outputFormat.audioFileTypeID else {
            throw NSError(description: "Output file must be caf, wav or aif but it is \(outputFormat)")
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
        var status: OSStatus = noErr

        func closeFiles() {
            if let inputFile {
                if noErr != ExtAudioFileDispose(inputFile) {
                    Log.error("Error disposing input file at \(inputURL)")
                }
            }

            if let outputFile {
                if noErr != ExtAudioFileDispose(outputFile) {
                    Log.error("Error disposing output file at \(outputURL)")
                }
            }

            inputFile = nil
            outputFile = nil
        }

        // make sure these are closed on any exit to avoid leaking the file objects
        defer {
            closeFiles()
        }

        if noErr != ExtAudioFileOpenURL(inputURL as CFURL, &inputFile) {
            throw NSError(description: "Unable to open the input file.")
        }

        guard let strongInputFile = inputFile else {
            throw NSError(description: "Unable to open the input file.")
        }

        var inputDescription = AudioStreamBasicDescription()
        var inputDescriptionSize = UInt32(MemoryLayout.stride(ofValue: inputDescription))

        if noErr != ExtAudioFileGetProperty(
            strongInputFile,
            kExtAudioFileProperty_FileDataFormat,
            &inputDescriptionSize,
            &inputDescription
        ) {
            throw NSError(description: "Unable to get the input file data format.")
        }

        var outputDescription = AudioFormatConverter.createOutputDescription(
            options: source.options,
            outputFormatID: format,
            inputDescription: inputDescription
        )

        let inputFormat = inputURL.pathExtension.lowercased()

        guard inputFormat != outputFormat.pathExtension ||
            outputDescription.mSampleRate != inputDescription.mSampleRate ||
            outputDescription.mChannelsPerFrame != inputDescription.mChannelsPerFrame ||
            outputDescription.mBitsPerChannel != inputDescription.mBitsPerChannel else {
            Log.error("No conversion is needed, formats are the same. Copying to", outputURL)

            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return
        }

        // Create destination file
        status = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            format,
            &outputDescription,
            nil,
            AudioFileFlags.eraseFile.rawValue, // overwrite old file if present
            &outputFile
        )

        if status != noErr {
            let message = "Unable to create output file at \(outputURL.path). dstFormat \(outputDescription) Error: \(status.string) (\(status.fourCC)"

            throw NSError(description: message)
        }

        guard let strongOutputFile = outputFile else {
            throw NSError(description: "Output file is nil.")
        }

        // The format must be linear PCM (kAudioFormatLinearPCM).
        // You must set this in order to encode or decode a non-PCM file data format.
        // You may set this on PCM files to specify the data format used in your calls
        // to read/write.
        if noErr != ExtAudioFileSetProperty(
            strongInputFile,
            kExtAudioFileProperty_ClientDataFormat,
            inputDescriptionSize,
            &outputDescription
        ) {
            throw NSError(description: "Unable to set data format on input file.")
        }

        if noErr != ExtAudioFileSetProperty(
            strongOutputFile,
            kExtAudioFileProperty_ClientDataFormat,
            inputDescriptionSize,
            &outputDescription
        ) {
            throw NSError(description: "Unable to set the output file data format.")
        }

        let bufferByteSize: UInt32 = 32768
        var srcBuffer = [UInt8](repeating: 0, count: Int(bufferByteSize))
        var sourceFrameOffset: UInt32 = 0

        var error: Error?

        srcBuffer.withUnsafeMutableBytes { srcBufferPtr in
            while true {
                let mBuffer = AudioBuffer(
                    mNumberChannels: inputDescription.mChannelsPerFrame,
                    mDataByteSize: bufferByteSize,
                    mData: srcBufferPtr.baseAddress
                )

                var fillBufList = AudioBufferList(mNumberBuffers: 1,
                                                  mBuffers: mBuffer)
                var frameCount: UInt32 = 0

                if outputDescription.mBytesPerFrame > 0 {
                    frameCount = bufferByteSize / outputDescription.mBytesPerFrame
                }

                let readError = ExtAudioFileRead(strongInputFile, &frameCount, &fillBufList)

                if noErr != readError {
                    error = NSError(code: Int(readError), description: "Error reading from the input file.")
                    break
                }

                // EOF
                if frameCount == 0 {
                    break
                }

                sourceFrameOffset += frameCount

                let writeError = ExtAudioFileWrite(strongOutputFile, frameCount, &fillBufList)

                if noErr != writeError {
                    error = NSError(code: Int(writeError), description: "Error writing to the output file.")
                    break
                }
            }
        }

        if let error {
            throw error
        }
    }
}

extension AudioFormatConverter {
    public static func createOutputDescription(
        options: AudioFormatConverterOptions,
        outputFormatID: AudioFormatID,
        inputDescription: AudioStreamBasicDescription
    ) -> AudioStreamBasicDescription {
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

        return AudioStreamBasicDescription(
            mSampleRate: mSampleRate,
            mFormatID: mFormatID,
            mFormatFlags: mFormatFlags,
            mBytesPerPacket: mBytesPerPacket,
            mFramesPerPacket: 1,
            mBytesPerFrame: mBytesPerFrame,
            mChannelsPerFrame: mChannelsPerFrame,
            mBitsPerChannel: mBitsPerChannel,
            mReserved: 0
        )
    }
}
