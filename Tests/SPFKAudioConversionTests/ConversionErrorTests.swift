// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
class ConversionErrorTests: BinTestCase {
    // MARK: - .error

    @Test func eraseFileFalseThrowsWhenOutputExists() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        // First conversion creates the output file
        let converter1 = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter1.start()
        #expect(output.exists)

        // Second conversion with eraseFile = false should throw
        var options = AudioFormatConverterOptions()
        options.conflictScheme = .error

        let converter2 = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        await #expect(throws: Error.self) {
            try await converter2.start()
        }
    }

    // MARK: - .overwrite

    @Test func eraseFileTrueOverwritesExistingOutput() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        // First conversion
        let converter1 = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter1.start()
        #expect(output.exists)

        // Second conversion with eraseFile = true (default) should succeed
        var options = AudioFormatConverterOptions()
        options.conflictScheme = .overwrite

        let converter2 = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter2.start()
        #expect(output.exists)
    }

    // MARK: - .unique

    @Test func uniqueSchemeRenamesOutputWhenExists() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        // First conversion creates the output file
        let converter1 = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter1.start()
        #expect(output.exists)

        // Second conversion with .unique should write to a renamed file
        var options = AudioFormatConverterOptions()
        options.conflictScheme = .unique

        let converter2 = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter2.start()

        // Original file still exists, unchanged
        #expect(output.exists)

        // Renamed output was created with _1 suffix
        let base = output.deletingPathExtension().lastPathComponent
        let ext = output.pathExtension
        let renamedOutput = bin.appending(component: "\(base)_1.\(ext)", directoryHint: .notDirectory)
        #expect(renamedOutput.exists)
    }

    // MARK: - Output is the input

    enum OutputSpelling: String, CaseIterable {
        case identical
        case throughSymlinkedDirectory
        case differentCase
    }

    /// The source's own folder and format, spelled three ways a path comparison would miss.
    @Test(arguments: OutputSpelling.allCases, FileConflictScheme.allCases)
    func refusesAnOutputThatIsItsOwnInput(spelling: OutputSpelling, scheme: FileConflictScheme) async throws {
        let directory = bin.appending(component: "real", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let input = directory.appending(component: "source.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.tabla_wav, to: input)
        let expectedLength = try AVAudioFile(forReading: input).length

        let output: URL

        switch spelling {
        case .identical:
            output = input

        case .throughSymlinkedDirectory:
            let alias = bin.appending(component: "alias", directoryHint: .isDirectory)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
            output = alias.appending(component: "source.wav", directoryHint: .notDirectory)

        case .differentCase:
            let values = try bin.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            try #require(values.volumeSupportsCaseSensitiveNames == false)
            output = directory.appending(component: "SOURCE.wav", directoryHint: .notDirectory)
        }

        var options = AudioFormatConverterOptions()
        options.conflictScheme = scheme

        let converter = AudioFormatConverter(inputURL: input, outputURL: output, options: options)

        await #expect(throws: AudioFormatConverterError.outputReplacesInput(input)) {
            try await converter.start()
        }

        try #require(input.exists)
        #expect(try AVAudioFile(forReading: input).length == expectedLength)
    }

    /// A pending edit converts from a render, so the file that must survive is not the input.
    @Test func refusesAnOutputThatIsTheFileARenderStandsIn() async throws {
        let original = bin.appending(component: "original.wav", directoryHint: .notDirectory)
        let render = bin.appending(component: "render.wav", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.tabla_wav, to: original)
        try FileManager.default.copyItem(at: TestBundleResources.shared.cowbell_wav, to: render)

        // A different file for the render, so replacing the original is visible and not only deleting it.
        let expectedLength = try AVAudioFile(forReading: original).length
        try #require(try AVAudioFile(forReading: render).length != expectedLength)

        let source = AudioFormatConverterSource(
            input: render,
            output: original,
            options: AudioFormatConverterOptions(),
            originalInput: original
        )

        await #expect(throws: AudioFormatConverterError.outputReplacesInput(original)) {
            try await AudioFormatConverter(source: source).start()
        }

        try #require(original.exists)
        #expect(try AVAudioFile(forReading: original).length == expectedLength)
    }

    /// A non-first track is decoded to an intermediate before any conflict handling, so the
    /// refusal has to come ahead of that branch as well.
    @Test func refusesAnOutputThatIsItsOwnInputWhenATrackIsSelected() async throws {
        let input = bin.appending(component: "dualaudio.m4a", directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: TestBundleResources.shared.dualaudio_m4a, to: input)

        let descriptions = await AudioTrackReader.read(from: input)
        let japanese = try #require(descriptions.first { $0.language == "jpn" })
        try #require(descriptions.first?.id != japanese.id)

        var source = AudioFormatConverterSource(input: input, output: input, options: AudioFormatConverterOptions())
        source.audioTrack = japanese.id

        await #expect(throws: AudioFormatConverterError.outputReplacesInput(input)) {
            try await AudioFormatConverter(source: source).start()
        }

        #expect(await AudioTrackReader.read(from: input).count == descriptions.count)
    }

    // MARK: - Invalid input

    @Test func invalidInputURLThrows() async throws {
        let input = URL(fileURLWithPath: "/nonexistent/audio.wav")
        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: input, outputURL: output)
        await #expect(throws: Error.self) {
            try await converter.start()
        }
    }

    @Test func unsupportedInputExtensionThrows() async throws {
        // Create a dummy file with an unsupported extension
        let fakeInput = bin.appending(component: "test.xyz", directoryHint: .notDirectory)
        try Data("not audio".utf8).write(to: fakeInput)

        let output = bin.appending(component: "\(#function).wav", directoryHint: .notDirectory)

        let converter = AudioFormatConverter(inputURL: fakeInput, outputURL: output)
        await #expect(throws: Error.self) {
            try await converter.start()
        }
    }
}
