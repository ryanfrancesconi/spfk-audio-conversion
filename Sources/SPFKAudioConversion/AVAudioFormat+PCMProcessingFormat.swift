// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation

extension AVAudioFormat {
    /// Deinterleaved 32-bit float at `sampleRate`: what every PCM source here decodes to.
    ///
    /// One and two channels are the standard formats, so they compare equal to formats built
    /// elsewhere. More channels carry `layout`, or a discrete layout when it is `nil` or names a
    /// different channel count. `nil` only for zero channels or an unusable rate.
    public static func pcmProcessingFormat(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        layout: AVAudioChannelLayout?
    ) -> AVAudioFormat? {
        guard channelCount > 0, sampleRate > 0 else { return nil }

        guard channelCount > 2 else {
            return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)
        }

        let matching = layout.flatMap { $0.channelCount == channelCount ? $0 : nil }

        guard let resolved = matching ?? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channelCount) else {
            return nil
        }

        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: resolved)
    }

    /// ``pcmProcessingFormat(sampleRate:channelCount:layout:)`` for a layout named by its tag.
    public static func pcmProcessingFormat(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        layoutTag: AudioChannelLayoutTag?
    ) -> AVAudioFormat? {
        pcmProcessingFormat(
            sampleRate: sampleRate,
            channelCount: channelCount,
            layout: layoutTag.flatMap(AVAudioChannelLayout.init(layoutTag:))
        )
    }
}
