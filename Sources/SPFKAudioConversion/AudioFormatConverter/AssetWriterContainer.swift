// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKBase

/// The AV Objects are being quarantined to this struct to allow Swift 6 to
/// agree to them.
struct AssetWriterContainer: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let writerInput: AVAssetWriterInput
    let readerOutput: AVAssetReaderTrackOutput

    init(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput,
        readerOutput: AVAssetReaderTrackOutput
    ) {
        self.reader = reader
        self.writer = writer
        self.writerInput = writerInput
        self.readerOutput = readerOutput
    }

    // TODO: macOS 26 adds async AVAssetWriter APIs (outputProvider(for:), inputReceiver(for:),
    // SampleBufferReceiver.append). Initial attempts to use them here resulted in either a crash
    // ("Must start a session") or an indefinite hang at receiver.append(). The legacy
    // requestMediaDataWhenReady path works correctly on all platforms including macOS 26,
    // so we use it unconditionally until the new APIs stabilize.
    func start() async throws {
        try await _startLegacy()
    }

    private func _startLegacy() async throws {
        writer.add(writerInput)
        reader.add(readerOutput)

        if !writer.startWriting() {
            throw writer.error ?? NSError(description: "Failed to start writing")
        }

        writer.startSession(atSourceTime: .zero)

        if !reader.startReading() {
            throw reader.error ?? NSError(description: "Failed to start reading")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.spongefork.AudioFormatConverter")
            let resumeGuard = ContinuationResumeGuard()

            writerInput.requestMediaDataWhenReady(
                on: queue,
                using: {
                    while writerInput.isReadyForMoreMediaData {
                        guard reader.status == .reading,
                            let buffer = readerOutput.copyNextSampleBuffer()
                        else {
                            writerInput.markAsFinished()

                            if resumeGuard.tryResume() {
                                if reader.status != .completed {
                                    writer.cancelWriting()
                                    continuation.resume(
                                        throwing: reader.error ?? NSError(description: "Conversion failed with error"))
                                } else {
                                    continuation.resume()
                                }
                            }

                            break
                        }

                        writerInput.append(buffer)
                    }
                }
            )
        }

        await writer.finishWriting()
    }
}

/// Thread-safe guard to ensure a continuation is only resumed once.
private final class ContinuationResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    /// Returns `true` exactly once; subsequent calls return `false`.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
