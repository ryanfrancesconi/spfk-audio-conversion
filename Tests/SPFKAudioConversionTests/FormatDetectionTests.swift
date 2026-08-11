// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct FormatDetectionTests {
    // MARK: - Output format routing

    /// An output file does not exist when it is classified, so ``AudioFormatConverter/isCompressed(url:)``
    /// cannot inspect it and answers from its extension list alone. A supported output format
    /// missing from that list is therefore read as PCM and routed to `convertToPCM`, which throws
    /// for anything but wav/aiff/caf — the whole failure, with no hint of the real cause.
    @Test func supportedOutputFormatsAreClassifiedForTheirRoute() {
        // The formats `convertToPCM` can actually write.
        let pcmWritable: Set<AudioFileType> = [.wav, .aiff, .caf]

        for format in AudioFormatConverterOptions.supportedOutputFormats {
            // A path that does not exist, which is the state every output is classified in.
            let url = URL(fileURLWithPath: "/nonexistent/output.\(format.pathExtension)")
            let isPCM = AudioFormatConverter.isPCM(url: url) == true

            #expect(
                isPCM == pcmWritable.contains(format),
                "\(format.pathExtension) routes to the wrong converter"
            )
        }
    }

    // MARK: - isCompressed by path extension

    @Test func wavIsNotCompressed() {
        let result = AudioFormatConverter.isCompressed(url: TestBundleResources.shared.tabla_wav)
        #expect(result == false)
    }

    @Test func aifIsNotCompressed() {
        let result = AudioFormatConverter.isCompressed(url: TestBundleResources.shared.tabla_aif)
        #expect(result == false)
    }

    @Test func cafIsNotCompressed() {
        let result = AudioFormatConverter.isCompressed(url: TestBundleResources.shared.tabla_caf)
        #expect(result == false)
    }

    @Test func m4aIsCompressed() {
        let result = AudioFormatConverter.isCompressed(url: TestBundleResources.shared.tabla_m4a)
        #expect(result == true)
    }

    @Test func mp3IsCompressed() {
        let result = AudioFormatConverter.isCompressed(url: TestBundleResources.shared.tabla_mp3)
        #expect(result == true)
    }

    @Test func mp4IsCompressed() {
        let result = AudioFormatConverter.isCompressed(url: TestBundleResources.shared.tabla_mp4)
        #expect(result == true)
    }

    // MARK: - isPCM

    @Test func isPCMReturnsTrueForWav() {
        let result = AudioFormatConverter.isPCM(url: TestBundleResources.shared.tabla_wav)
        #expect(result == true)
    }

    @Test func isPCMReturnsFalseForM4A() {
        let result = AudioFormatConverter.isPCM(url: TestBundleResources.shared.tabla_m4a)
        #expect(result == false)
    }

    // MARK: - isCompressed with deep inspection

    @Test func isCompressedWithDeepInspectionForWav() {
        let result = AudioFormatConverter.isCompressed(
            url: TestBundleResources.shared.tabla_wav,
            ignorePathExtension: true
        )
        #expect(result == false)
    }

    @Test func isCompressedWithDeepInspectionForM4A() {
        let result = AudioFormatConverter.isCompressed(
            url: TestBundleResources.shared.tabla_m4a,
            ignorePathExtension: true
        )
        #expect(result == true)
    }

    @Test func isCompressedReturnsNilForNonexistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/file.xyz")
        let result = AudioFormatConverter.isCompressed(url: url, ignorePathExtension: true)
        #expect(result == nil)
    }

    // MARK: - isPCM with deep inspection

    @Test func isPCMWithDeepInspectionForWav() {
        let result = AudioFormatConverter.isPCM(
            url: TestBundleResources.shared.tabla_wav,
            ignorePathExtension: true
        )
        #expect(result == true)
    }

    @Test func isPCMWithDeepInspectionForM4A() {
        let result = AudioFormatConverter.isPCM(
            url: TestBundleResources.shared.tabla_m4a,
            ignorePathExtension: true
        )
        #expect(result == false)
    }

    @Test func isPCMReturnsNilForNonexistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/file.xyz")
        let result = AudioFormatConverter.isPCM(url: url, ignorePathExtension: true)
        #expect(result == nil)
    }

    @Test func isPCMReturnsTrueForAIFF() {
        let result = AudioFormatConverter.isPCM(url: TestBundleResources.shared.tabla_aif)
        #expect(result == true)
    }

    @Test func isPCMReturnsTrueForCAF() {
        let result = AudioFormatConverter.isPCM(url: TestBundleResources.shared.tabla_caf)
        #expect(result == true)
    }

    @Test func isPCMReturnsFalseForMP3() {
        let result = AudioFormatConverter.isPCM(url: TestBundleResources.shared.tabla_mp3)
        #expect(result == false)
    }

    // MARK: - outputPathExtensions

    @Test func outputPathExtensionsMatchOutputFormats() {
        let expected = AudioFormatConverter.outputFormats.map(\.pathExtension)
        #expect(AudioFormatConverter.outputPathExtensions == expected)
    }
}
