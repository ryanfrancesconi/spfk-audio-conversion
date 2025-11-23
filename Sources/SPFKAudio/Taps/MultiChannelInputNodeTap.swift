// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import OTAtomics
import OTCore
import SPFKBase

// MARK: - Needs Refactor

/// MultiChannelInputNodeTap is a tap intended to process multiple channels of audio
/// from AVAudioInputNode, or the AVAudioEngine's inputNode. In the case of the engine,
/// the input node will have a set of channels that correspond to the hardware being
/// used. This class will read from those channels and write discrete mono files for
/// each similar to how common DAWs record multiple channels from multiple inputs.
public final class MultiChannelInputNodeTap {
    public enum Event {
        case tapInstalled
        case tapRemoved
        case dataReceived(frameLength: AVAudioFrameCount, time: AVAudioTime)
    }

    /// a file name and its associated input channel
    public struct FileChannel {
        /// the track name
        var name: String
        /// 0 indexed
        var channel: Int32

        public init(name: String, channel: Int32) {
            self.name = name
            self.channel = channel
        }
    }

    /// Receive update events during the lifecyle of this class
    public weak var delegate: MultiChannelInputNodeTapDelegate?

    /// A simple name and channel pair for each channel being recorded
    public private(set) var fileChannels: [FileChannel]? {
        didSet {
            guard let fileChannels = fileChannels else { return }
            channelMap = fileChannels.map { $0.channel }
        }
    }

    /// Collection of the files being recorded to
    @OTAtomicsThreadSafe public var files = [WriteableFile]()

    /// This node has one element. The format of the input scope reflects the audio
    /// hardware sample rate and channel count.
    public private(set) var inputNode: AVAudioInputNode?

    /// Is this class currently recording?
    @OTAtomicsThreadSafe private(set) var isRecording = false {
        didSet {
            if isRecording {
                startedAtTime = AVAudioTime(hostTime: mach_absolute_time())

                Log.debug("⏺", files.count, " to record", startedAtTime)
                _ = files.map {
                    $0.createFile()
                }
            } else {
                stoppedAtTime = AVAudioTime(hostTime: mach_absolute_time())
                Log.debug("⏹", files.count, "recorded", stoppedAtTime)
            }
        }
    }

    /// Records wave files, could be expanded in the future
    public private(set) var recordFileType = "wav"

    /// the incoming format from the audioUnit after the channel mapping.
    /// Any number of channels of audio data
    public private(set) var recordFormat: AVAudioFormat?

    /// the temp format of the buffer during processing, generally mono
    @OTAtomicsThreadSafe public private(set) var bufferFormat: AVAudioFormat?

    /// the ultimate file format to write to disk
    public private(set) var fileFormat: AVAudioFormat?

    /// sample rate for all formats and files, this will be pulled from the
    /// format of the AVAudioInputNode
    public private(set) var sampleRate: Double = 48000

    /// fileFormat and bufferFormat
    public private(set) var channels: UInt32 = 1

    /// fileFormat only
    public private(set) var bitsPerChannel: UInt32 = 24

    private var _bufferSize: AVAudioFrameCount = 2048

    /// The requested size of the incoming buffers. The implementation may choose another size.
    /// I'm seeing it set to 4800 on macOS in general. Given that I'm unclear why they offer
    /// us a choice
    public var bufferSize: AVAudioFrameCount {
        get { _bufferSize }
        set {
            _bufferSize = newValue
            // Log.debug("Attempting to set bufferSize to", newValue, "The implementation may choose another size.")
        }
    }

    @OTAtomicsThreadSafe private var _recordEnabled: Bool = false

    /// Call to start watching the inputNode's incoming audio data.
    /// Enables pre-recording monitoring, but must be enabled before recording as well.
    /// If not enabled when record() is called, it will be enabled then. This is important
    /// for showing audio input activity before actually printing to file.
    public var recordEnabled: Bool {
        get { _recordEnabled }
        set {
            guard let inputNode,
                  recordFormat != nil,
                  newValue != _recordEnabled else { return }

            _recordEnabled = newValue

            if _recordEnabled {
                // Log.debug("🚰 Installing Tap with format", recordFormat, "requested bufferSize", bufferSize)

                inputNode.installTap(
                    onBus: 0,
                    bufferSize: bufferSize,
                    format: recordFormat,
                    block: process(buffer:time:)
                )

                delegate?.tapInstalled(self, on: inputNode)

            } else {
                // Log.debug("🚰 Removing Tap")

                inputNode.removeTap(onBus: 0)

                delegate?.tapRemoved(self, from: inputNode)
            }
        }
    }

    /// Base directory where to write files too such as an Audio Files directory.
    /// You must set this prior to recording
    public var directory: URL?

    private var _recordCounter: Int = 1

    /// How many takes this class has done. Useful for naming output files by index
    public var recordCounter: Int {
        get { _recordCounter }
        set {
            _recordCounter = max(1, newValue)
        }
    }

    private var filesReady = false

    /// Timestamp when recording is started
    public private(set) var startedAtTime: AVAudioTime?

    /// Timestamp when recording is stopped
    public private(set) var stoppedAtTime: AVAudioTime?

    /// How long the class was recording based on the startedAtTime and stoppedAtTime timestamps
    public var durationRecorded: TimeInterval? {
        guard let startedAtTime,
              let stoppedAtTime else {
            return nil
        }
        return AVAudioTime.seconds(forHostTime: stoppedAtTime.hostTime) -
            AVAudioTime.seconds(forHostTime: startedAtTime.hostTime)
    }

    /// This property is used to map input channels from an input (source) to a destination.
    /// The number of channels represented in the channel map is the number of channels of the destination. The channel map entries
    /// contain a channel number of the source that should be mapped to that destination channel. If -1 is specified, then that
    /// destination channel will not contain any channel from the source (so it will be silent)
    private var _channelMap: [Int32] = []
    private var channelMap: [Int32] {
        get { _channelMap }
        set {
            guard newValue != _channelMap else { return }

            // Log.debug("Attempting to update channelMap to", newValue)

            guard let audioUnit = inputNode?.audioUnit else {
                Log.error("inputNode.audioUnit is nil")
                return
            }
            let channelMapSize = UInt32(MemoryLayout<Int32>.size * newValue.count)

            // 1 is the 'input' element, 0 is output
            let inputElement: AudioUnitElement = 1

            if noErr != AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_ChannelMap,
                kAudioUnitScope_Output,
                inputElement,
                newValue,
                channelMapSize
            ) {
                Log.error("Failed setting channel map")
                return
            }

            _channelMap = newValue
            recordFormat = createRecordFormat(channelMap: newValue)
            recordEnabled = false

            // Log.debug("Updated channelMap to", _channelMap)
        }
    }

    /// Optional latency offset that you should set after determining the correct latency
    /// for your hardware. This amount of samples will be skipped by the first write.
    /// While AVAudioInputNode provides a `presentationLatency` value, I don't see the
    /// value returned being accurate on macOS. For lack of the CoreAudio latency
    /// calculations, you could use that value. Default value is zero.
    public var ioLatency: AVAudioFrameCount = 0

    // MARK: - Init

    /// Currently assuming to write mono files based on the channelMap
    public init(inputNode: AVAudioInputNode) {
        self.inputNode = inputNode

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

    /// Convenience function for testing
    public func prepare(channelMap: [Int32]) {
        let fileChannels = channelMap.map {
            MultiChannelInputNodeTap.FileChannel(
                name: "Audio \($0 + 1)",
                channel: $0)
        }
        prepare(fileChannels: fileChannels)
    }

    /// Called with name and input channel pair. This allows you to associate
    /// a filename with an incoming channel.
    /// - Parameter fileChannels: Name + Channel pairs to record to
    public func prepare(fileChannels: [FileChannel]) {
        self.fileChannels = fileChannels
        initFormats()
        createFiles()
        recordEnabled = true
    }

    // MARK: - Formats

    private func initFormats() {
        bufferFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)

        fileFormat = AVAudioFormat.createPCMFormat(
            bitsPerChannel: bitsPerChannel,
            channels: channels,
            sampleRate: sampleRate
        )
    }

    private func createRecordFormat(channelMap: [Int32]) -> AVAudioFormat? {
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

    private func createFiles() {
        guard let directory,
              let fileFormat,
              let recordFormat,
              let fileChannels else {
            Log.error("File Format is nil")
            return
        }

        guard recordFormat.channelCount == channelMap.count else {
            Log.error("Channel count mismatch", recordFormat.channelCount, "vs", channelMap.count)
            return
        }

        // remove last batch of files
        files.removeAll()

        for i in 0 ..< fileChannels.count {
            let channel = fileChannels[i].channel
            let name = fileChannels[i].name

            guard let url = getNextURL(directory: directory, name: name, startIndex: recordCounter) else {
                Log.error("Failed to create URL in", directory, "with name", name)
                continue
            }

            // clobber - TODO: make it an option
            if FileManager.default.fileExists(atPath: url.path) {
                Log.error("Warning, deleting existing record file at", url)
                try? FileManager.default.removeItem(at: url)
            }

            // Log.debug("Creating destination:", url.path)

            let channelObject = WriteableFile(url: url,
                                              fileFormat: fileFormat,
                                              channel: channel,
                                              ioLatency: ioLatency)

            files.append(channelObject)
        }

        // Log.debug("Created", files, "latency in frames", ioLatency)

        filesReady = files.count == fileChannels.count

        // record counter to be saved in the project and restored
        recordCounter += 1
    }

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

    var writeTask: Task<Void, Error>?

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
            delegate?.dataWritten(self, at: time)
        }
    }

    /// The tap is running as long as recordEnable is true. This just sets a flag that says
    /// write to file in the process block
    public func record() {
        guard !isRecording else {
            return
        }

        isRecording = true

        if !filesReady { createFiles() }

        // could also enforce explicitly calling recordEnable
        if !recordEnabled { recordEnabled = true }

        Log.debug("⏺ Recording \(files.count) files using format", recordFormat.debugDescription)
    }

    /// Stops recording and closes files
    public func stop() {
        guard isRecording else {
            return
        }

        isRecording = false
        filesReady = false

        for i in 0 ..< files.count {
            // release reference to the file. will close it and make it readable from url.
            files[i].close()
        }

        Log.debug("⏹", files.count, "files")
    }
}

public protocol MultiChannelInputNodeTapDelegate: AnyObject {
    func tapInstalled(_ nodeInputTap: MultiChannelInputNodeTap, on node: AVAudioInputNode)
    func tapRemoved(_ nodeInputTap: MultiChannelInputNodeTap, from node: AVAudioInputNode)
    func dataWritten(_ nodeInputTap: MultiChannelInputNodeTap, at time: AVAudioTime)
}
