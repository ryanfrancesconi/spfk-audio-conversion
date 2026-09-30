// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation

extension AVAudioFrameCount {
    /// `frames` as a buffer frame count, or a thrown ``AudioFormatConverterError/tooLongToRender(_:)``
    /// naming `url` where plain narrowing would trap.
    static func checked(_ frames: Int64, for url: URL) throws -> AVAudioFrameCount {
        guard let count = AVAudioFrameCount(exactly: frames) else {
            throw AudioFormatConverterError.tooLongToRender(url)
        }

        return count
    }

    /// The same for a computed count, rounded up, which may also be infinite or NaN.
    static func checked(roundingUp frames: Double, for url: URL) throws -> AVAudioFrameCount {
        guard frames.isFinite, let count = AVAudioFrameCount(exactly: frames.rounded(.up)) else {
            throw AudioFormatConverterError.tooLongToRender(url)
        }

        return count
    }
}
