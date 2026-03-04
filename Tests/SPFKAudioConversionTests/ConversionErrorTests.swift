// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class ConversionErrorTests: BinTestCase {
    // MARK: - eraseFile = false

    @Test func eraseFileFalseThrowsWhenOutputExists() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        // First conversion creates the output file
        let converter1 = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter1.start()
        #expect(output.exists)

        // Second conversion with eraseFile = false should throw
        var options = AudioFormatConverterOptions()
        options.eraseFile = false

        let converter2 = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        await #expect(throws: Error.self) {
            try await converter2.start()
        }
    }

    // MARK: - eraseFile = true

    @Test func eraseFileTrueOverwritesExistingOutput() async throws {
        let input = TestBundleResources.shared.tabla_wav
        let output = bin.appending(component: "\(#function).aiff", directoryHint: .notDirectory)

        // First conversion
        let converter1 = AudioFormatConverter(inputURL: input, outputURL: output)
        try await converter1.start()
        #expect(output.exists)

        // Second conversion with eraseFile = true (default) should succeed
        var options = AudioFormatConverterOptions()
        options.eraseFile = true

        let converter2 = AudioFormatConverter(inputURL: input, outputURL: output, options: options)
        try await converter2.start()
        #expect(output.exists)
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
