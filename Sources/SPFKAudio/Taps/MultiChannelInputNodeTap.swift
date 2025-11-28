// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import SPFKAudioHardware
import SPFKBase
import SwiftExtensions

/// MultiChannelInputNodeTap is a tap intended to process multiple channels of audio
/// from AVAudioInputNode, or the AVAudioEngine's inputNode. In the case of the engine,
/// the input node will have a set of channels that correspond to the hardware being
/// used. This class will read from those channels and write discrete mono files for
/// each similar to how common DAWs record multiple channels from multiple inputs.
public actor MultiChannelInputNodeTap {
    public enum Event {
        case tapInstalled
        case tapRemoved
        case dataReceived(frameLength: AVAudioFrameCount, time: AVAudioTime)
    }

    /// Receive update events during the lifecyle of this class
    public weak var delegate: MultiChannelInputNodeTapDelegate?

    /// Collection of the files being recorded to
    public var files = [WriteableFile]()

    /// This node has one element. The format of the input scope reflects the audio
    /// hardware sample rate and channel count.
    public private(set) var inputNode: AVAudioInputNode?

    /// Is this class currently recording?
    private(set) var isRecording = false

    /// Records wave files, could be expanded in the future
    public private(set) var recordFileType = "wav"

    /// the incoming format from the audioUnit after the channel mapping.
    /// Any number of channels of audio data
    public private(set) var recordFormat: AVAudioFormat?

    /// the temp format of the buffer during processing, generally mono
    public private(set) var bufferFormat: AVAudioFormat?

    /// the ultimate file format to write to disk
    public private(set) var fileFormat: AVAudioFormat?

    /// sample rate for all formats and files, this will be pulled from the
    /// format of the AVAudioInputNode
    public private(set) var sampleRate: Double = 48000

    /// fileFormat and bufferFormat
    public private(set) var channels: UInt32 = 1

    /// fileFormat only
    public private(set) var bitsPerChannel: UInt32 = 24

    /// The requested size of the incoming buffers. The implementation may choose another size.
    public var bufferSize: AVAudioFrameCount = 2048

    public var recordEnabled: Bool { tapInstalled }

    var tapInstalled: Bool = false

    /// Call to start watching the inputNode's incoming audio data.
    /// Enables pre-recording monitoring, but must be enabled before recording as well.
    /// If not enabled when record() is called, it will be enabled then. This is important
    /// for showing audio input activity before actually printing to file.
    public func update(recordEnabled newValue: Bool) throws {
        guard newValue != recordEnabled else { return }

        guard let inputNode else {
            throw NSError(description: "inputNode is nil")
        }

        guard let recordFormat else {
            throw NSError(description: "recordFormat is nil")
        }

        if newValue {
            Log.debug("⏺ Installing Tap with format", recordFormat, "requested bufferSize", bufferSize)

            try createFiles()

            inputNode.installTap(
                onBus: 0,
                bufferSize: bufferSize,
                format: recordFormat,
                block: process(buffer:time:)
            )

            setInstalled(true)

        } else {
            Log.debug("⏺ Removing Tap")

            inputNode.removeTap(onBus: 0)
            setInstalled(false)
        }
    }

    private func setInstalled(_ state: Bool) {
        guard let delegate else { return }

        tapInstalled = state

        state ?
            delegate.tapInstalled() :
            delegate.tapRemoved()
    }

    /// Base directory where to write files too such as an Audio Files directory.
    /// You must set this prior to recording
    private var directory: URL?
    public func update(directory: URL) {
        self.directory = directory
    }

    private var _recordCounter: Int = 1

    /// How many takes this class has done. Useful for naming output files by index
    public var recordCounter: Int {
        get { _recordCounter }
        set {
            _recordCounter = max(1, newValue)
        }
    }

    public func resetRecordCounter() {
        recordCounter = 1
    }

    public func updateRecordCounter(to value: Int) {
        recordCounter = value
    }

    private var filesReady = false

    /// Timestamp when recording is started
    public private(set) var startedAtTime: AVAudioTime?

    /// Timestamp when recording is stopped
    public private(set) var stoppedAtTime: AVAudioTime?

    /// How long the class was recording based on the startedAtTime and stoppedAtTime timestamps
    public var durationRecorded: TimeInterval? {
        guard let startedAtTime,
              let stoppedAtTime
        else {
            return nil
        }
        return AVAudioTime.seconds(forHostTime: stoppedAtTime.hostTime) -
            AVAudioTime.seconds(forHostTime: startedAtTime.hostTime)
    }

    private var fileChannels: [AudioDeviceNamedChannel] = []

    /// This property is used to map input channels from an input (source) to a destination.
    /// The number of channels represented in the channel map is the number of channels of the destination. The channel map entries
    /// contain a channel number of the source that should be mapped to that destination channel. If -1 is specified, then that
    /// destination channel will not contain any channel from the source (so it will be silent)
    private var channelMap: [UInt32] = []

    /// Optional latency offset that you should set after determining the correct latency
    /// for your hardware. This amount of samples will be skipped by the first write.
    /// While AVAudioInputNode provides a `presentationLatency` value, I don't see the
    /// value returned being accurate on macOS. For lack of the CoreAudio latency
    /// calculations, you could use that value. Default value is zero.
    private var ioLatency: AVAudioFrameCount = 0

    public func update(ioLatency: AVAudioFrameCount) {
        self.ioLatency = ioLatency
    }

    // MARK: - Init

    /// Currently assuming to write mono files based on the channelMap
    public init(inputNode: AVAudioInputNode, delegate: MultiChannelInputNodeTapDelegate?) {
        self.inputNode = inputNode
        self.delegate = delegate

        let outputFormat = inputNode.outputFormat(forBus: 0)

        sampleRate = outputFormat.sampleRate

        Log.debug("inputNode", outputFormat.channelCount, "channels at", sampleRate, "Hz")
    }

    public func dispose() {
        files.removeAll()
        inputNode = nil
        delegate = nil
    }

    deinit {
        Log.debug("* { MultiChannelInputNodeTap }")
    }

    /// Called with name and input channel pair. This allows you to associate
    /// a filename with an incoming channel.
    ///
    /// - Parameter fileChannels: Name + Channel pairs to record to
    public func prepare(fileChannels: [AudioDeviceNamedChannel]) throws {
        guard fileChannels.isNotEmpty else {
            throw NSError(description: "file channels is empty")
        }

        self.fileChannels = fileChannels

        let channelMap = fileChannels.map { $0.channel }

        try update(channelMap: channelMap)

        initFormats()

        try update(recordEnabled: true)
    }

    private func update(channelMap newValue: [UInt32]) throws {
        guard newValue != channelMap else { return }

        Log.debug("Attempting to update channelMap to", newValue)

        guard let audioUnit = inputNode?.audioUnit else {
            throw NSError(description: "inputNode.audioUnit is nil")
        }

        let channelMapSize = UInt32(MemoryLayout<Int32>.size * newValue.count)

        // 1 is the 'input' element, 0 is output
        let inputElement: AudioUnitElement = 1

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Output,
            inputElement,
            newValue,
            channelMapSize
        )

        guard noErr == status else {
            throw NSError(description: "Failed setting channel map with error \(status.fourCC)")
        }

        channelMap = newValue

        recordFormat = createRecordFormat(channelMap: newValue)
    }

    // MARK: - Formats

    private func initFormats() {
        bufferFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        )

        fileFormat = AVAudioFormat.createPCMFormat(
            bitsPerChannel: bitsPerChannel,
            channels: channels,
            sampleRate: sampleRate
        )
    }

    private func createRecordFormat(channelMap: [UInt32]) -> AVAudioFormat? {
        guard !channelMap.isEmpty else {
            Log.error("You must specify a valid channel map")
            return nil
        }

        let layoutTag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelMap.count)

        guard let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag) else {
            Log.error("Failed creating AVAudioChannelLayout")
            return nil
        }

        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: channelLayout)
    }

    private func createFiles() throws {
        guard let directory else {
            throw NSError(description: "directory is nil")
        }

        guard let fileFormat else {
            throw NSError(description: "fileFormat is nil")
        }

        guard let recordFormat else {
            throw NSError(description: "recordFormat is nil")
        }

        guard recordFormat.channelCount == channelMap.count else {
            throw NSError(description: "Channel count mismatch: \(recordFormat.channelCount) vs \(channelMap.count)")
        }

        // remove last batch of files
        files.removeAll()

        for i in 0 ..< fileChannels.count {
            let channel = fileChannels[i].channel
            let name = fileChannels[i].name ?? "Audio"

            guard let url = getNextURL(directory: directory, name: name, startIndex: recordCounter) else {
                Log.error("Failed to create URL in", directory, "with name", name)
                continue
            }

            // clobber - TODO: make it an option
            if url.exists {
                Log.error("Warning, deleting existing record file at", url)
                try? url.delete()
            }

            // Log.debug("Creating destination:", url.path)

            let channelObject = try WriteableFile(
                url: url,
                fileFormat: fileFormat,
                channel: channel,
                ioLatency: ioLatency
            )

            files.append(channelObject)
        }

        // Log.debug("Created", files, "latency in frames", ioLatency)

        filesReady = files.count == fileChannels.count

        // record counter to be saved in the project and restored
        recordCounter += 1
    }

    // AVAudioNodeTapBlock
    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let bufferFormat else {
            Log.error("bufferFormat is nil")
            return
        }

        // will contain all channels of audio being recorded
        guard let channelData = buffer.floatChannelData else {
            Log.error("buffer.floatChannelData is nil")
            return
        }

        let channelCount = Int(buffer.format.channelCount)

        assert(files.count == channelCount)

        for channel in 0 ..< channelCount {
            // a temp buffer used to write this chunk to the file
            guard let channelBuffer = AVAudioPCMBuffer(
                pcmFormat: bufferFormat,
                frameCapacity: buffer.frameLength
            ) else {
                Log.error("Failed creating channelBuffer")
                return
            }

            for i in 0 ..< Int(buffer.frameLength) {
                channelBuffer.floatChannelData?[0][i] = channelData[channel][i]
            }

            channelBuffer.frameLength = buffer.frameLength

            guard files.indices.contains(channel) else {
                Log.error("Count mismatch")
                return
            }

            do {
                try files[channel].process(
                    buffer: channelBuffer,
                    time: time,
                    write: isRecording
                )

            } catch {
                Log.error("Write failed", error)
            }
        }

        if recordEnabled {
            delegate?.dataWritten()
        }
    }

    /// The tap is running as long as recordEnable is true. This just sets a flag that says
    /// write to file in the process block
    public func record() throws {
        guard !isRecording else {
            return
        }

        isRecording = true
        startedAtTime = AVAudioTime(hostTime: mach_absolute_time())

        if !filesReady {
            try createFiles()
        }

        for file in files {
            file.createFile()
        }

        // could also enforce explicitly calling recordEnable
        if !recordEnabled {
            try update(recordEnabled: true)
        }

        Log.debug("⏺ Recording \(files.count) files using format", recordFormat.debugDescription)
    }

    /// Stops recording and closes files
    public func stop() {
        guard isRecording else {
            return
        }

        isRecording = false
        stoppedAtTime = AVAudioTime(hostTime: mach_absolute_time())

        filesReady = false

        for file in files {
            file.close()
        }

        Log.debug("⏹", files.count, "files recorded")
    }
}

extension MultiChannelInputNodeTap {
    // switch to Utils version
    private func getNextURL(directory: URL, name: String, startIndex: Int) -> URL? {
        let url = directory.appendingPathComponent(name).appendingPathExtension(recordFileType)
        let pathExtension = url.pathExtension
        let baseFilename = url.deletingPathExtension().lastPathComponent

        for i in startIndex ... 10000 {
            let filename = "\(baseFilename) #\(i)"
            let test = directory.appendingPathComponent(filename)
                .appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: test.path) { return test }
        }
        return nil
    }
}

public protocol MultiChannelInputNodeTapDelegate: AnyObject {
    func tapInstalled()
    func tapRemoved()
    func dataWritten()
}
