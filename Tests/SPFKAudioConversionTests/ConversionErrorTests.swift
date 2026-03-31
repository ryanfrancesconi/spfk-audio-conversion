// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
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
