// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioConverterC
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.serialized, .tags(.file))
class LameConverterTests: BinTestCase {

    // MARK: - Helpers

    private func makeWAV(
        frames: Int,
        sampleRate: Double = 44100,
        channels: AVAudioChannelCount = 1,
        name: String
    ) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)

        if let data = buffer.floatChannelData {
            for ch in 0 ..< Int(channels) {
                for i in 0 ..< frames {
                    data[ch][i] = Float(sin(Double(i) * .pi * 2.0 * 440.0 / sampleRate)) * 0.5
                }
            }
        }

        let url = bin.appending(component: "\(name).wav", directoryHint: .notDirectory)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
        // file is deallocated here — WAV headers are finalized before the caller passes the path to LAME
    }

    // MARK: - Basic conversion

    @Test func convertMonoWAVToMP3CBR() throws {
        let input = try makeWAV(frames: 44100, name: "lame_mono_cbr_in")
        let output = bin.appending(component: "lame_mono_cbr_out.mp3", directoryHint: .notDirectory)

        let status = LameConverter().convert(toMP3: input.path, output: output.path, bitRate: 128, quality: 2)
        #expect(status == 0)
        #expect(output.exists)
        let fileSize = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        #expect(fileSize > 0)
    }

    @Test func convertStereoWAVToMP3CBR() throws {
        let input = try makeWAV(frames: 44100, channels: 2, name: "lame_stereo_cbr_in")
        let output = bin.appending(component: "lame_stereo_cbr_out.mp3", directoryHint: .notDirectory)

        let status = LameConverter().convert(toMP3:input.path, output: output.path, bitRate: 256, quality: 2)
        #expect(status == 0)
        #expect(output.exists)
    }

    @Test func convertToMP3VBR() throws {
        let input = try makeWAV(frames: 44100, name: "lame_vbr_in")
        let output = bin.appending(component: "lame_vbr_out.mp3", directoryHint: .notDirectory)

        // bitRate == 0 → VBR mode
        let status = LameConverter().convert(toMP3:input.path, output: output.path, bitRate: 0, quality: 2)
        #expect(status == 0)
        #expect(output.exists)
    }

    // MARK: - Xing/Info header regression

    /// Regression: LameConverter previously opened the output with "wb" (write-only), preventing
    /// lame_mp3_tags_fid() from seeking back to update the Xing header. AVAudioFile.length returns 0
    /// for MP3 files missing a valid Xing/Info frame.
    @Test func cbrOutputHasNonZeroFrameLength() throws {
        let input = try makeWAV(frames: 44100, name: "lame_xing_cbr_in")
        let output = bin.appending(component: "lame_xing_cbr_out.mp3", directoryHint: .notDirectory)

        let status = LameConverter().convert(toMP3: input.path, output: output.path, bitRate: 128, quality: 2)
        #expect(status == 0)

        let result = try AVAudioFile(forReading: output)
        #expect(result.length > 0, "CBR Info header must report frame count; got length=\(result.length)")
    }

    @Test func vbrOutputHasNonZeroFrameLength() throws {
        let input = try makeWAV(frames: 44100, name: "lame_xing_vbr_in")
        let output = bin.appending(component: "lame_xing_vbr_out.mp3", directoryHint: .notDirectory)

        let status = LameConverter().convert(toMP3:input.path, output: output.path, bitRate: 0, quality: 2)
        #expect(status == 0)

        let result = try AVAudioFile(forReading: output)
        #expect(result.length > 0, "VBR Xing header must report frame count; got length=\(result.length)")
    }

    // MARK: - Duration fidelity

    @Test func outputDurationApproximatelyMatchesInput() throws {
        let sampleRate: Double = 44100
        let frames = Int(sampleRate * 2.0)
        let input = try makeWAV(frames: frames, sampleRate: sampleRate, name: "lame_duration_in")
        let output = bin.appending(component: "lame_duration_out.mp3", directoryHint: .notDirectory)

        _ = LameConverter().convert(toMP3:input.path, output: output.path, bitRate: 128, quality: 2)

        let result = try AVAudioFile(forReading: output)
        let outputDuration = Double(result.length) / result.fileFormat.sampleRate
        // ±5% tolerance for encoder delay and frame padding
        #expect(abs(outputDuration - 2.0) < 0.1, "Expected ~2s, got \(outputDuration)s")
    }

    // MARK: - Short clip edge case

    /// Less than one MPEG frame (1152 samples at 44100 Hz). lame_encode_flush() must produce output.
    @Test func shortClipProducesNonEmptyOutput() throws {
        let frames = Int(44100 * 0.02) // 20 ms — well under one MPEG frame
        let input = try makeWAV(frames: frames, name: "lame_short_in")
        let output = bin.appending(component: "lame_short_out.mp3", directoryHint: .notDirectory)

        let status = LameConverter().convert(toMP3: input.path, output: output.path, bitRate: 128, quality: 2)
        #expect(status == 0)

        let result = try AVAudioFile(forReading: output)
        #expect(result.length > 0, "Short clip must still produce a non-empty MP3")
    }

    // MARK: - Error paths

    @Test func invalidInputPathReturnsError() {
        let output = bin.appending(component: "lame_bad_in_out.mp3", directoryHint: .notDirectory)
        let status = LameConverter().convert(toMP3:
            "/nonexistent/path/audio.wav", output: output.path, bitRate: 128, quality: 2
        )
        #expect(status != 0)
    }

    @Test func invalidOutputPathReturnsError() throws {
        let input = try makeWAV(frames: 44100, name: "lame_bad_out_in")
        let status = LameConverter().convert(toMP3:
            input.path, output: "/nonexistent/dir/output.mp3", bitRate: 128, quality: 2
        )
        #expect(status != 0)
    }
}
