// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct AudioFileReadErrorTests {
    @Test("a failed read reports the frame it started at and the file's length")
    func readFailureNamesPosition() throws {
        let file = try AVAudioFile(forReading: TestBundleResources.shared.tabla_wav)
        file.framePosition = 1000

        // A buffer whose channel count differs from the file's cannot be read into.
        let channels: AVAudioChannelCount = file.processingFormat.channelCount == 1 ? 2 : 1
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: channels))
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))

        #expect {
            try ReversedAudioBuilder.readToEnd(file, into: chunk, frameCount: 4096)
        } throws: { error in
            guard case let AudioFileReadError.readFailed(url, framePosition, length, _)? = error as? AudioFileReadError else { return false }
            return url.lastPathComponent == "tabla.wav" && framePosition == 1000 && length == file.length
        }
    }

    @Test("a failed open names the file")
    func openFailureNamesFile() {
        let url = URL(fileURLWithPath: "/nonexistent/missing.wav")

        #expect {
            _ = try AVAudioFilePCMSource(url: url)
        } throws: { error in
            guard case AudioFileReadError.openFailed? = error as? AudioFileReadError else { return false }
            return error.localizedDescription.hasPrefix("missing.wav could not be opened (")
        }
    }

    @Test("reading stops at the file's length without the read past the end")
    func readStopsAtLength() throws {
        let file = try EndFailingAudioFile(forReading: TestBundleResources.shared.tabla_wav)
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1 << 15))
        var total: AVAudioFramePosition = 0

        while true {
            try ReversedAudioBuilder.readToEnd(file, into: chunk, frameCount: 1 << 15)
            guard chunk.frameLength > 0 else { break }
            total += AVAudioFramePosition(chunk.frameLength)
        }

        #expect(total == file.length)
    }
}

/// Fails a read past the end with no description, as Swift reports an Objective-C call that set no
/// error.
private final class EndFailingAudioFile: AVAudioFile {
    override func read(into buffer: AVAudioPCMBuffer, frameCount frames: AVAudioFrameCount) throws {
        guard framePosition < length else {
            throw NSError(domain: "Foundation._GenericObjCError", code: 0)
        }
        try super.read(into: buffer, frameCount: frames)
    }
}
