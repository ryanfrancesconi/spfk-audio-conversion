// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKTempo

extension AudioEditRenderer {
    /// The source frames to read either side of `window` for the stretcher, as far as the file has
    /// them. Zero for an edit with no time/pitch.
    func readContext(
        around window: (offset: AVAudioFrameCount, frameCount: AVAudioFrameCount),
        totalFrames: AVAudioFrameCount,
        format: AVAudioFormat
    ) throws -> (before: AVAudioFrameCount, after: AVAudioFrameCount) {
        guard !edit.timePitch.isEmpty else { return (0, 0) }

        let needed = try TimePitchRenderer.contextFrames(
            for: edit.timePitch,
            sampleRate: format.sampleRate,
            channelCount: Int(stretchChannelCount(forInput: format.channelCount)),
            quality: renderSettings.timePitchQuality
        )

        let end = window.offset + window.frameCount
        let before = min(AVAudioFrameCount(clamping: needed.pre), window.offset)
        let after = min(AVAudioFrameCount(clamping: needed.post), totalFrames - min(totalFrames, end))

        return (before, after)
    }

    /// `window` of a file read whole, cut out with its context. A file with no time/pitch keeps the
    /// whole buffer, to be trimmed by the source stages.
    func withContext(
        of window: (offset: AVAudioFrameCount, frameCount: AVAudioFrameCount),
        in whole: AVAudioPCMBuffer,
        edit: AudioEditDescription
    ) throws -> RenderWindow {
        guard !edit.timePitch.isEmpty, window.offset > 0 || window.frameCount < whole.frameLength else {
            return RenderWindow(buffer: whole, edit: edit, isPreTrimmed: false)
        }

        let context = try readContext(around: window, totalFrames: whole.frameLength, format: whole.format)
        let frames = context.before + window.frameCount + context.after

        guard let buffer = AVAudioPCMBuffer(pcmFormat: whole.format, frameCapacity: frames) else {
            throw NSError(description: "Failed to allocate PCM buffer for \(sourceURL.lastPathComponent)")
        }

        try buffer.copy(from: whole, readOffset: window.offset - context.before, frames: frames)

        return RenderWindow(
            buffer: buffer,
            edit: edit,
            isPreTrimmed: true,
            contextBefore: Int(context.before),
            contextAfter: Int(context.after)
        )
    }

    /// The window's channel steps, reverse and time/pitch, with the context taking the same steps
    /// so it reaches the stretcher in the material's layout. Reversed, the source's post-context
    /// leads the material.
    func stretched(_ window: RenderWindow) async throws -> AVAudioPCMBuffer {
        let edit = window.edit
        let total = Int(window.buffer.frameLength)
        let leading = edit.isReversed ? window.contextAfter : window.contextBefore
        let trailing = edit.isReversed ? window.contextBefore : window.contextAfter
        let material = leading ..< max(leading, total - trailing)

        let conformed = try Self.conforming(window.buffer.applyingChannelOperation(edit.channels), toMono: conformToMono)

        // Handed to the stretcher and awaited; nothing else holds it meanwhile.
        nonisolated(unsafe) let input = edit.isReversed ? try conformed.reverse() : conformed

        let output = try await TimePitchRenderer.render(
            input,
            material: material,
            description: edit.timePitch,
            quality: renderSettings.timePitchQuality
        )

        let expected = edit.timePitch.outputFrameCount(forInput: material.count)

        guard Int(output.frameLength) == expected else {
            throw NSError(
                description: "The time/pitch render of \(sourceURL.lastPathComponent) produced \(output.frameLength) frames, not \(expected)"
            )
        }

        return output
    }

    /// The channels the stretcher sees: after the edit's channel operation and the mono conform.
    func stretchChannelCount(forInput channels: AVAudioChannelCount) -> AVAudioChannelCount {
        let count = edit.channels.outputChannelCount(forInput: channels)
        return conformToMono != nil && count == 2 ? 1 : count
    }

    /// Writes the BPM and key a stretch or transposition implies over the copied tags: BPM × rate
    /// (tag and iXML), and the key moved by whole semitones into the key tag, out of the comment
    /// if that is where it was. Only a tag the source carried is rewritten, and only when the
    /// render copies text metadata.
    func rewriteTimePitchTags(of url: URL) throws {
        let timePitch = edit.timePitch
        let semitones = Int((timePitch.pitchCents / 100).rounded(.toNearestOrAwayFromZero))

        guard metadataCopyScheme.includesText,
              timePitch.rate != 1 || semitones != 0,
              let fileType = AudioFileType(pathExtension: url.pathExtension),
              AudioFileType.metadataTypes.contains(fileType)
        else { return }

        var properties = try TagProperties(url: url)
        var changed = false

        if timePitch.rate != 1,
           let scaled = properties[.bpm].flatMap(Bpm.init(parsing:))?.scaled(by: timePitch.rate) {
            properties.set(tag: .bpm, value: scaled.stringValue)
            changed = true
        }

        if semitones != 0 {
            if let resolved = MusicalKeyValue.resolve(initialKey: properties[.initialKey], comment: properties[.comment]),
               let transposed = resolved.key.value.transposed(bySemitones: semitones).string(in: .standard)
            {
                properties.setInitialKey(transposed, notation: keyNotation)

                if case let .comment(remainder) = resolved.source {
                    properties.set(tag: .comment, value: remainder.isEmpty ? nil : remainder)
                }

                changed = true

            } else if let key = properties[.initialKey], !key.trimmingCharacters(in: .whitespaces).isEmpty {
                Log.error("The key \"\(key)\" of \(sourceURL.lastPathComponent) does not parse, so it was not transposed")
            }
        }

        if changed {
            try properties.save(to: url)
        }

        guard timePitch.rate != 1,
              [.wav, .flac].contains(fileType),
              let xml = ProductionChunks.readIXML(from: url, fileType: fileType)
        else { return }

        var ixml = try IXMLMetadata(xml: xml)

        guard var fields = ixml.userFields,
              let scaled = fields.bpm.flatMap(Bpm.init(parsing:))?.scaled(by: timePitch.rate)
        else { return }

        fields.bpm = scaled.stringValue
        ixml.setUserFields(fields)
        try ProductionChunks.writeIXML(ixml.xml, to: url, fileType: fileType)
    }
}
