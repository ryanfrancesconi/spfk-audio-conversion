// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKUtils
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
class AssetWriterErrorTests: BinTestCase {
    // MARK: - Nil format throws

    @Test func nilFormatThrows() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = nil

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)

        await #expect(throws: Error.self) {
            try await writer.start()
        }
    }

    // MARK: - Unsupported format throws

    @Test func unsupportedFormatThrows() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).flac", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .flac // rejected by setter, stays nil

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)

        await #expect(throws: Error.self) {
            try await writer.start()
        }
    }

    // MARK: - M4A caps sample rate at 48kHz

    @Test func m4aCapsHighSampleRate() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a
        options.sampleRate = 96000

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter.start()

        #expect(output.exists)

        let outputFile = try AVAudioFile(forReading: output)
        // M4A should cap at 48kHz
        #expect(outputFile.fileFormat.sampleRate <= 48000)
    }

    // MARK: - A failed writer is reported

    /// Runs the conversion onto a volume with less free space than the output needs.
    ///
    /// The reader completes normally in this case and `append` keeps returning `true` — only
    /// `finishWriting()` reports the failure, and it leaves a file at the destination either way.
    @Test func fullDiskConversionThrows() async throws {
        deleteBinOnExit = true

        let image = bin.appending(component: "tiny.dmg", directoryHint: .notDirectory)
        let mount = bin.appending(component: "tiny", directoryHint: .isDirectory)

        try hdiutil(["create", "-size", "8m", "-fs", "HFS+", "-volname", "tiny", "-quiet", image.path])
        try hdiutil(["attach", image.path, "-nobrowse", "-quiet", "-mountpoint", mount.path])

        defer { _ = try? hdiutil(["detach", mount.path, "-force", "-quiet"]) }

        // Leave less headroom than 4.8 seconds of 320 kbps AAC needs, and more than the writer
        // needs to start.
        let available = try mount.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity ?? 0
        let filler = mount.appending(component: "filler", directoryHint: .notDirectory)
        try Data(count: max(0, available - 64 * 1024)).write(to: filler)

        var options = AudioFormatConverterOptions()
        options.format = .m4a
        options.bitRate = 320_000

        let converter = AudioFormatConverter(
            inputURL: TestBundleResources.shared.tabla_wav,
            outputURL: mount.appending(component: "out.m4a", directoryHint: .notDirectory),
            options: options
        )

        await #expect(throws: Error.self) {
            try await converter.start()
        }
    }

    @discardableResult
    private func hdiutil(_ args: [String]) throws -> String {
        let handler = ProcessHandler(url: URL(fileURLWithPath: "/usr/bin/hdiutil"), args: args)
        let output = try handler.run()

        guard handler.process.terminationStatus == 0 else {
            throw NSError(description: "hdiutil \(args.first ?? "") failed: \(output)")
        }

        return output
    }

    // MARK: - PCM to M4A succeeds

    @Test func pcmToM4ASucceeds() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).m4a", directoryHint: .notDirectory)

        var options = AudioFormatConverterOptions()
        options.format = .m4a

        let source = AudioFormatConverterSource(input: input, output: output, options: options)
        let writer = AssetWriter(source: source)
        try await writer.start()

        #expect(output.exists)
        let outputFile = try AVAudioFile(forReading: output)
        #expect(outputFile.duration > 0)
    }
}
