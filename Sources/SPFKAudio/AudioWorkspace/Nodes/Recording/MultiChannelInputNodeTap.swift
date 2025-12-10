// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKAudioHardware
import SPFKBase
import SwiftExtensions

/// MultiChannelInputNodeTap is a tap intended to process multiple channels of audio
/// from AVAudioInputNode (the AVAudioEngine's inputNode). In the case of the engine,
/// the input node will have a set of channels that correspond to the hardware being
/// used. This class will read from those channels and write discrete mono files for
/// each similar to how common DAWs record multiple channels from multiple inputs.
public actor MultiChannelInputNodeTap {
    public enum Event {
        case started
        case stopped
        case isEnabled(Bool)
        case dataReceived(frameLength: AVAudioFrameCount, time: AVAudioTime)
    }

    /// Receive update events during the life cyle of this class
    public weak var delegate: MultiChannelInputNodeTapDelegate?
    public func update(delegate: MultiChannelInputNodeTapDelegate?) {
        self.delegate = delegate
    }

    /// Collection of the files being recorded to
    private var files = [WriteableFile]()

    public var fileProperties: [WriteableFileProperties] {
        files.map(\.properties)
    }

    /// This node has one element. The format of the input scope reflects the audio
    /// hardware sample rate and channel count.
    public let inputNode: AVAudioInputNode

    public var engine: AVAudioEngine? { inputNode.engine }

    /// Is this class currently recording?
    public private(set) var isRecording = false

    /// Records wave files, could be expanded in the future
    public private(set) var recordFileType = "wav"

    /// the incoming format from the audioUnit after the channel mapping.
    /// Any number of channels of audio data
    public private(set) var recordFormat: AVAudioFormat?

    /// the temp format of the buffer during processing, generally mono
    public private(set) var singleChannelFormat: AVAudioFormat?

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

        guard let recordFormat else {
            throw NSError(description: "recordFormat is nil")
        }

        if newValue {
            Log.debug(
                "⏺ Installing Tap with format", recordFormat, "requested bufferSize", bufferSize,
            )

            try createFiles()

            try ExceptionTrap.withThrowing { [unowned self] in
                inputNode.engine?.pause()

                // make sure this bus is available
                inputNode.removeTap(onBus: 0)

                inputNode.installTap(
                    onBus: 0,
                    bufferSize: bufferSize,
                    format: recordFormat,
                    block: process(buffer:time:),
                )

                // seems to be necessary at the moment though the documentation says otherwise
                try inputNode.engine?.start()

                setInstalled(true)
            }

        } else {
            Log.debug("⏺ Removing Tap")

            try ExceptionTrap.withThrowing { [unowned self] in
                inputNode.removeTap(onBus: 0)
                setInstalled(false)
            }
        }
    }

    private func setInstalled(_ state: Bool) {
        guard let delegate else { return }

        tapInstalled = state

        delegate.multiChannelInputNodeTap(event: .isEnabled(state))
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
        return AVAudioTime.seconds(forHostTime: stoppedAtTime.hostTime)
            - AVAudioTime.seconds(forHostTime: startedAtTime.hostTime)
    }

    private var fileChannels: [AudioDeviceNamedChannel] = []

    /// This property is used to map input channels from an input (source) to a destination.
    /// The number of channels represented in the channel map is the number of channels of the destination. The channel
    /// map entries
    /// contain a channel number of the source that should be mapped to that destination channel. If -1 is specified,
    /// then that
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
    public init(inputNode: AVAudioInputNode, directory: URL?, delegate: MultiChannelInputNodeTapDelegate?) {
        self.inputNode = inputNode
        self.directory = directory
        self.delegate = delegate

        let outputFormat = inputNode.outputFormat(forBus: 0)

        sampleRate = outputFormat.sampleRate

        Log.debug("inputNode", outputFormat.channelCount, "channels at", sampleRate, "Hz")
    }

    deinit {
        Log.debug("- { \(self) }")
    }

    public func dispose() {
        files.removeAll()
        delegate = nil
    }

    /// Called with name and input channel pair. This allows you to associate
    /// a filename with an incoming channel.
    ///
    /// - Parameter fileChannels: Name + Channel pairs to record to
    public func prepare(fileChannels: [AudioDeviceNamedChannel]) throws {
        if isRecording {
            stop()
        }

        guard fileChannels.isNotEmpty else {
            throw NSError(description: "file channels is empty")
        }

        self.fileChannels = fileChannels

        let channelMap = fileChannels.map(\.channel)

        try update(channelMap: channelMap)

        try initFormats()
    }

    private func update(channelMap newValue: [UInt32]) throws {
        guard newValue != channelMap else { return }

        Log.debug("Attempting to update channelMap to", newValue)

        try inputNode.update(channelMap: newValue)

        channelMap = newValue
        recordFormat = createRecordFormat(channelMap: newValue)
    }

    // MARK: - Formats

    private func initFormats() throws {
        singleChannelFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels,
        )

        fileFormat = AVAudioFormat.createPCMFormat(
            bitsPerChannel: bitsPerChannel,
            channels: channels,
            sampleRate: sampleRate,
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
        guard !filesReady else { return }

        guard let directory else {
            throw NSError(description: "createFiles() directory is nil")
        }

        guard let fileFormat else {
            throw NSError(description: "createFiles() fileFormat is nil")
        }

        guard let recordFormat else {
            throw NSError(description: "createFiles() recordFormat is nil")
        }

        guard recordFormat.channelCount == channelMap.count else {
            throw NSError(
                description:
                "createFiles() Channel count mismatch: \(recordFormat.channelCount) vs \(channelMap.count)",
            )
        }

        files.forEach { $0.close() }

        // remove last batch of files
        files.removeAll()

        for i in 0 ..< fileChannels.count {
            let channel = fileChannels[i].channel
            let name = fileChannels[i].name ?? "Audio"

            guard let url = getNextURL(directory: directory, name: name, startIndex: recordCounter)
            else {
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
                ioLatency: ioLatency,
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
        guard let singleChannelFormat else {
            Log.error("singleChannelFormat is nil")
            return
        }

        // will contain all channels of audio being recorded in one buffer
        guard let floatChannelData = buffer.floatChannelData else {
            Log.error("buffer.floatChannelData is nil")
            return
        }

        let channelCount = Int(buffer.format.channelCount)

        assert(files.count == channelCount)

        guard channelCount > 1 else {
            process(channelIndex: 0, singleChannelBuffer: buffer, time: time)
            return
        }

        // separate the channels as each will go to a different file target
        for channelIndex in 0 ..< channelCount {
            // a temp buffer used to write this channel to the file
            guard
                let singleChannelBuffer = AVAudioPCMBuffer(
                    pcmFormat: singleChannelFormat,
                    frameCapacity: buffer.frameLength,
                )
            else {
                Log.error("Failed creating singleChannelBuffer")
                return
            }

            guard let destinationPointer = singleChannelBuffer.floatChannelData?[0] else {
                Log.error("Failed to get singleChannelBuffer pointer")
                return
            }

            // Copy data for the current channel
            let sourcePointer = floatChannelData[channelIndex]
            let size = Int(buffer.frameLength) * MemoryLayout<Float>.size
            memcpy(destinationPointer, sourcePointer, size)

            singleChannelBuffer.frameLength = buffer.frameLength

            process(channelIndex: channelIndex, singleChannelBuffer: singleChannelBuffer, time: time)
        }

        if recordEnabled {
            delegate?.multiChannelInputNodeTap(
                event: .dataReceived(frameLength: buffer.frameLength, time: time)
            )
        }
    }

    private func process(channelIndex: Int, singleChannelBuffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard files.indices.contains(channelIndex) else {
            Log.error("Count mismatch")
            return
        }

        do {
            try files[channelIndex].process(
                buffer: singleChannelBuffer,
                time: time,
                write: isRecording,
            )

        } catch {
            Log.error("Write failed", error)
            assertionFailure(error.localizedDescription)
        }
    }

    /// The tap is open as long as `recordEnabled` is true. This just sets a flag (`isRecording`) that says
    /// write these buffers to file in the process block
    public func record() throws {
        guard !isRecording else {
            return
        }

        // could also enforce explicitly calling recordEnable
        if !recordEnabled {
            try update(recordEnabled: true)
        }

        if !filesReady {
            try createFiles()
        }

        for file in files {
            try file.open() // create the AVAudioFile
        }

        isRecording = true
        startedAtTime = AVAudioTime(hostTime: mach_absolute_time())

        delegate?.multiChannelInputNodeTap(event: .started)
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

        delegate?.multiChannelInputNodeTap(event: .stopped)
        Log.debug("⏹", files.count, "files recorded")
    }
}

extension MultiChannelInputNodeTap {
    private func getNextURL(directory: URL, name: String, startIndex: Int) -> URL? {
        let url =
            directory
                .appendingPathComponent(name)
                .appendingPathExtension(recordFileType)

        let pathExtension = url.pathExtension
        let baseFilename = url.deletingPathExtension().lastPathComponent

        let endIndex = startIndex + 10000

        for i in startIndex ... endIndex {
            let filename = "\(baseFilename) #\(i)"

            let test =
                directory
                    .appendingPathComponent(filename)
                    .appendingPathExtension(pathExtension)

            if !test.exists {
                return test
            }
        }

        return nil
    }
}

public protocol MultiChannelInputNodeTapDelegate: AnyObject, Sendable {
    func multiChannelInputNodeTap(event: MultiChannelInputNodeTap.Event)
}
