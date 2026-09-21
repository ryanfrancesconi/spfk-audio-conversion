// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMatroska
import SPFKTesting
import SPFKVideo
import Testing

@testable import SPFKAudioConversion

/// A pending edit renders from the audio track the row plays, not the container's first.
@Suite(.tags(.file))
class AudioEditRendererTrackTests: BinTestCase {
    /// The fixtures' tracks are a 440 Hz and an 880 Hz tone; the second is the 880.
    private static let secondTrackFrequency: Double = 880

    private func secondTrackID(of url: URL) async throws -> AudioTrackDescription.ID {
        let tracks = AudioFileType(pathExtension: url.pathExtension)?.isMatroska == true
            ? try MatroskaFile(url: url).audioTrackDescriptions
            : await AudioTrackReader.read(from: url)

        try #require(tracks.count == 2)
        return tracks[1].id
    }

    /// Zero crossings above a small guard band, which tells 440 from 880 without a transform.
    private func dominantFrequency(of url: URL) throws -> (frequency: Double, seconds: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        )
        try file.read(into: buffer)

        let data = try #require(buffer.floatChannelData)
        let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
        let seconds = Double(buffer.frameLength) / file.processingFormat.sampleRate

        var crossings = 0
        var lastSign = 0

        for sample in samples where abs(sample) > 0.05 {
            let sign = sample > 0 ? 1 : -1
            if lastSign != 0, sign != lastSign { crossings += 1 }
            lastSign = sign
        }

        return (Double(crossings) / 2 / seconds, seconds)
    }

    /// `dualaudio_mka` renders to WAV, since nothing here reads a Matroska output back through
    /// `AVAudioFile`; `dualaudio_m4a` renders into its own container, as a conversion's render does.
    @Test(arguments: [
        (TestBundleResources.shared.dualaudio_mka, "wav"),
        (TestBundleResources.shared.dualaudio_m4a, "m4a"),
    ])
    func aTrimOnTheSecondTrackRendersTheSecondTrack(source: URL, outputExtension: String) async throws {
        let output = bin.appending(component: "rendered.\(outputExtension)", directoryHint: .notDirectory)

        let renderer = AudioEditRenderer(
            sourceURL: source,
            audioTrack: try await secondTrackID(of: source),
            edit: AudioEditDescription(trim: TrimDescription(inPoint: 0.5, outPoint: 1.5)),
            outputURL: output
        )

        try await renderer.render()

        let measured = try dominantFrequency(of: output)

        #expect(abs(measured.frequency - Self.secondTrackFrequency) < 30)
        // AAC adds up to a packet of priming either side of the window.
        #expect(abs(measured.seconds - 1) < 0.05)
    }
}
