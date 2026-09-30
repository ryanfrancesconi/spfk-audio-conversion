// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

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
        try Task.checkCancellation()

        writer.add(writerInput)
        reader.add(readerOutput)

        if !writer.startWriting() {
            throw writer.error ?? NSError(description: "Failed to start writing")
        }

        writer.startSession(atSourceTime: .zero)

        if !reader.startReading() {
            throw reader.error ?? NSError(description: "Failed to start reading")
        }

        // The block below runs on AVFoundation's queue, outside any task, where `Task.isCancelled`
        // is always false; the flag is how a cancellation reaches it.
        let cancellation = CancellationFlag()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let queue = DispatchQueue(label: "com.spongefork.AudioFormatConverter")
                let resumeGuard = ContinuationResumeGuard()

                writerInput.requestMediaDataWhenReady(
                    on: queue,
                    using: {
                        while writerInput.isReadyForMoreMediaData {
                            if cancellation.isCancelled {
                                writerInput.markAsFinished()
                                reader.cancelReading()
                                writer.cancelWriting()

                                if resumeGuard.tryResume() {
                                    continuation.resume(throwing: CancellationError())
                                }

                                return
                            }

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

                            // A rejected buffer leaves the reader completing normally, so nothing
                            // below reports it.
                            if !writerInput.append(buffer) {
                                let error = writer.error ?? NSError(description: "The writer rejected a sample buffer")

                                writerInput.markAsFinished()
                                reader.cancelReading()
                                writer.cancelWriting()

                                if resumeGuard.tryResume() {
                                    continuation.resume(throwing: error)
                                }

                                return
                            }
                        }
                    }
                )
            }
        } onCancel: {
            cancellation.cancel()
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? NSError(description: "Writing \(writer.outputURL.lastPathComponent) failed")
        }
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

/// A cancellation raised on one thread and read on another.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}
