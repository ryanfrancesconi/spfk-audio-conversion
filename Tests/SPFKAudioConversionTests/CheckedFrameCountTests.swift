// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import AVFoundation
import Foundation
import Testing

@testable import SPFKAudioConversion

/// A frame count past `UInt32.max` is over six hours at 192 kHz, which one buffer cannot hold.
struct CheckedFrameCountTests {
    private let url = URL(filePath: "/long.wav")

    @Test func aCountThatFitsIsKept() throws {
        #expect(try AVAudioFrameCount.checked(Int64(UInt32.max), for: url) == UInt32.max)
        #expect(try AVAudioFrameCount.checked(0, for: url) == 0)
    }

    @Test func aCountPastOneBufferThrowsNamingTheFile() {
        #expect(throws: AudioFormatConverterError.tooLongToRender(url)) {
            try AVAudioFrameCount.checked(Int64(UInt32.max) + 1, for: url)
        }
    }

    @Test func aNegativeCountThrows() {
        #expect(throws: AudioFormatConverterError.tooLongToRender(url)) {
            try AVAudioFrameCount.checked(-1, for: url)
        }
    }

    @Test func aComputedCountRoundsUpOrThrows() throws {
        #expect(try AVAudioFrameCount.checked(roundingUp: 10.2, for: url) == 11)
        #expect(throws: AudioFormatConverterError.tooLongToRender(url)) {
            try AVAudioFrameCount.checked(roundingUp: .nan, for: url)
        }
        #expect(throws: AudioFormatConverterError.tooLongToRender(url)) {
            try AVAudioFrameCount.checked(roundingUp: Double(UInt32.max) + 1, for: url)
        }
    }
}
