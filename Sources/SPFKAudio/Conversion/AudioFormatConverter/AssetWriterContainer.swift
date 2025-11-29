// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

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
    ) throws {
        self.reader = reader
        self.writer = writer
        self.writerInput = writerInput
        self.readerOutput = readerOutput

        writer.add(writerInput)
        reader.add(readerOutput)

        if !writer.startWriting() {
            throw writer.error ?? NSError(description: "Failed to start writing")
        }

        writer.startSession(atSourceTime: .zero)

        if !reader.startReading() {
            throw reader.error ?? NSError(description: "Failed to start reading")
        }
    }

    // TODO: add macOS 26 version

    func start() async throws {
        if #available(macOS 26, iOS 26, *) {
            try await _start()

        } else {
            try await _startLegacy()
        }
    }

    private func _start() async throws {
        try await _startLegacy() // TODO:
    }

    private func _startLegacy() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.spongefork.AudioFormatConverter")

            writerInput.requestMediaDataWhenReady(
                on: queue,
                using: {
                    while writerInput.isReadyForMoreMediaData {
                        guard reader.status == .reading,
                              let buffer = readerOutput.copyNextSampleBuffer()
                        else {
                            writerInput.markAsFinished()

                            if reader.status != .completed {
                                writer.cancelWriting()
                                continuation.resume(
                                    throwing: reader.error ?? NSError(description: "Conversion failed with error"))
                            } else {
                                continuation.resume()
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
