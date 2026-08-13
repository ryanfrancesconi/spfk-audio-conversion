// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKAudioConversion
import SPFKBase

// Timings for the read paths, against a file long enough for their costs to separate. The bundled
// fixtures run a few seconds, where reading the whole file and reading a window of it measure the
// same.
//
// An executable, not a test suite, for two reasons: the numbers only mean anything compiled `-O`,
// and `-configuration Release` cannot run a test target that uses `@testable`. It asserts nothing —
// what counts as too slow is a judgement for `plans/spfk-audio-conversion-audit.md` Part 3.
//
// Run:
//   xcodebuild -workspace Spongefork.xcworkspace -scheme spfk-audio-conversion-bench \
//     -configuration Release -destination 'platform=macOS' \
//     -derivedDataPath /Users/rf/Documents/Dev/xcodebuild/cli-derived-data build
//   /Users/rf/Documents/Dev/xcodebuild/cli-derived-data/Build/Products/Release/spfk-audio-conversion-bench
//
// Takes minutes and one source duration as an optional argument:
//   spfk-audio-conversion-bench 600

// MARK: - Timing and footprint

/// This process's physical footprint right now, in MB.
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )

    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }

    guard result == KERN_SUCCESS else { return 0 }

    return Double(info.phys_footprint) / 1_048_576
}

/// Highest footprint seen while a phase runs. Sampled rather than read at the end: the buffers a
/// phase allocates are usually released before it returns, which is what makes the peak the
/// interesting number here.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Double = 0
    private var timer: DispatchSourceTimer?

    func start() {
        peak = footprintMB()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "footprint"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = footprintMB()
            lock.lock()
            peak = max(peak, current)
            lock.unlock()
        }
        timer.resume()

        self.timer = timer
    }

    func stop() -> Double {
        timer?.cancel()
        timer = nil

        lock.lock()
        defer { lock.unlock() }
        return peak
    }
}

@discardableResult
func measure(_ label: String, _ body: () async throws -> Void) async rethrows -> Double {
    let sampler = FootprintSampler()
    sampler.start()

    let start = DispatchTime.now().uptimeNanoseconds
    try await body()
    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

    let peak = sampler.stop()

    print(String(format: "  %-40@ %9.1f ms  peak %7.1f MB", label as NSString, ms, peak))
    return ms
}

func section(_ title: String) {
    print("\n\(title)")
    print(String(repeating: "-", count: 76))
}

// MARK: - Source

let sourceMinutes = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 10
let sourceSeconds = sourceMinutes * 60
let sampleRate: Double = 48000

let directory = FileManager.default.temporaryDirectory
    .appending(component: "spfk-audio-conversion-bench", directoryHint: .isDirectory)

try? FileManager.default.removeItem(at: directory)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let sourceURL = directory.appending(component: "source.wav", directoryHint: .notDirectory)

/// Writes a sine sweep of `sourceSeconds`, in chunks so the generator itself never holds the file.
func writeSource() throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    var file: AVAudioFile? = try AVAudioFile(
        forWriting: sourceURL,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )

    guard let format = file?.processingFormat,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)
    else {
        throw NSError(description: "Could not allocate the generator buffer")
    }

    var written: Double = 0

    while written < sourceSeconds {
        buffer.frameLength = buffer.frameCapacity

        for frame in 0 ..< Int(buffer.frameLength) {
            let t = written + Double(frame) / sampleRate
            let value = Float(sin(2 * .pi * (220 + 40 * sin(t * 0.1)) * t)) * 0.5

            buffer.floatChannelData?[0][frame] = value
            buffer.floatChannelData?[1][frame] = value
        }

        try file?.write(from: buffer)
        written += Double(buffer.frameLength) / sampleRate
    }

    file = nil
}

print("spfk-audio-conversion bench")
print(String(format: "source: %.0f s, %.0f Hz, 2ch, 24-bit", sourceSeconds, sampleRate))

try await measure("write the source") {
    try writeSource()
}

let sourceBytes = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
print(String(format: "        %.1f MB on disk", Double(sourceBytes) / 1_048_576))

// MARK: - 3.1 AudioEditRenderer

section("3.1 AudioEditRenderer — a short trim out of a long source")

for trimSeconds in [2.0, 30.0] {
    let output = directory.appending(
        component: "trim_\(Int(trimSeconds)).wav",
        directoryHint: .notDirectory
    )

    let edit = AudioEditDescription(
        trim: TrimDescription(inPoint: sourceSeconds / 2, outPoint: sourceSeconds / 2 + trimSeconds)
    )

    let renderer = AudioEditRenderer(
        sourceURL: sourceURL,
        edit: edit,
        outputURL: output,
        fileConflictScheme: .overwrite,
        metadataCopyScheme: .ignore
    )

    await measure(String(format: "render a %.0f s trim", trimSeconds)) {
        _ = try? await renderer.render()
    }
}

// MARK: - 3.1 SegmentDivider

section("3.1 SegmentDivider — the same read, once per segment")

for count in [4, 16] {
    let width = sourceSeconds / Double(count)
    let segments = (0 ..< count).map { i in
        TrimDescription(inPoint: Double(i) * width, outPoint: Double(i + 1) * width)
    }

    let outputDirectory = directory.appending(component: "segments_\(count)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let divider = SegmentDivider(
        sourceURL: sourceURL,
        segments: segments,
        outputDirectory: outputDirectory
    )

    await measure("divide into \(count) segments") {
        _ = try? await divider.divide()
    }
}

// MARK: - 3.2 AVAssetReaderPCMSource

section("3.2 AVAssetReaderPCMSource — a whole-file scan, as the waveform does it")

let scanSource = try await AVAssetReaderPCMSource(url: sourceURL)
let scanFormat = scanSource.processingFormat

if let buffer = AVAudioPCMBuffer(pcmFormat: scanFormat, frameCapacity: 16384) {
    var frames: AVAudioFramePosition = 0

    try await measure("scan to the end") {
        while true {
            let read = try scanSource.readNextChunk(into: buffer, frameCount: 16384)
            guard read > 0 else { break }
            frames += AVAudioFramePosition(read)
        }
    }

    print(String(format: "        %.1f s decoded", Double(frames) / scanFormat.sampleRate))
}

// MARK: - 3.3 ExtAudioFile

section("3.3 ExtAudioFile — PCM to PCM, 32 KB per round trip")

await measure("convert to 16-bit WAV") {
    var options = AudioFormatConverterOptions()
    options.format = .wav
    options.bitsPerChannel = 16

    let converter = AudioFormatConverter(
        inputURL: sourceURL,
        outputURL: directory.appending(component: "converted.wav", directoryHint: .notDirectory),
        options: options
    )
    _ = try? await converter.start()
}

print("\nscratch: \(directory.path)")
