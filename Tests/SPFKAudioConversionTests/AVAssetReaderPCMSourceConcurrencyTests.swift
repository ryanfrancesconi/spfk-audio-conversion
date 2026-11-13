// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import os
import SPFKAudioBase
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

/// `copyNextSampleBuffer` blocks its thread on decode work that needs a thread of its own, so with every
/// cooperative thread inside one, none finishes. Each case starts more whole-file reads than there are
/// cooperative threads.
@Suite(.tags(.file))
struct AVAssetReaderPCMSourceConcurrencyTests {
    private static var readerCount: Int { ProcessInfo.processInfo.activeProcessorCount + 2 }

    /// Reads `count` sources made by `makeSource` to their ends at once, and returns each one's frames.
    private func readConcurrently(
        _ what: String,
        seeksFirst: Bool = false,
        makeSource: @escaping @Sendable () async throws -> any SeekablePCMSource
    ) async throws -> [AVAudioFramePosition] {
        let count = Self.readerCount
        let watchdog = ReadWatchdog(seconds: 30, message: "\(count) concurrent \(what) reads never finished")
        defer { watchdog.cancel() }

        return try await withThrowingTaskGroup(of: AVAudioFramePosition.self) { group in
            for _ in 0 ..< count {
                group.addTask {
                    let source = try await makeSource()
                    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096))
                    var total: AVAudioFramePosition = 0

                    if seeksFirst {
                        try await source.seek(toFrame: AVAudioFramePosition(source.processingFormat.sampleRate))
                    }

                    while case let read = try await source.readNextChunk(into: buffer, frameCount: 4096), read > 0 {
                        total += AVAudioFramePosition(read)
                    }

                    return total
                }
            }

            return try await group.reduce(into: [AVAudioFramePosition]()) { $0.append($1) }
        }
    }

    private func expectAllRead(_ totals: [AVAudioFramePosition]) {
        #expect(totals.count == Self.readerCount)
        #expect(totals.allSatisfy { $0 > 0 })
    }

    @Test func moreWholeFileReadsThanCoresAllFinish() async throws {
        let url = TestBundleResources.shared.tabla_m4a

        try await expectAllRead(readConcurrently("AVAssetReaderPCMSource") {
            try await AVAssetReaderPCMSource(url: url)
        })
    }

    /// The seek decodes its preroll through the same blocking call.
    @Test func moreSeeksThanCoresAllFinish() async throws {
        let url = TestBundleResources.shared.tabla_m4a

        try await expectAllRead(readConcurrently("seeking AVAssetReaderPCMSource", seeksFirst: true) {
            try await AVAssetReaderPCMSource(url: url)
        })
    }

    /// A thread per call takes no limiter slot, so nothing but the threads themselves bounds it.
    @Test func moreOwnThreadReadsThanCoresAllFinish() async throws {
        let url = TestBundleResources.shared.tabla_m4a

        try await expectAllRead(readConcurrently("own-thread AVAssetReaderPCMSource", seeksFirst: true) {
            try await AVAssetReaderPCMSource(url: url, admission: .ownThread)
        })
    }

    /// The Matroska decoder reads inline, with no admission.
    @Test func moreMatroskaReadsThanCoresAllFinish() async throws {
        let url = TestBundleResources.shared.tabla_mka

        try await expectAllRead(readConcurrently("MatroskaAudioDecoder", seeksFirst: true) {
            try MatroskaAudioDecoder(url: url, audioTrack: nil)
        })
    }

    /// libsndfile reads inline, with no admission.
    @Test func moreSndFileReadsThanCoresAllFinish() async throws {
        let url = TestBundleResources.shared.surround_vorbis_ogg

        try await expectAllRead(readConcurrently("SndFilePCMSource") {
            try SndFilePCMSource(url: url)
        })
    }
}

/// Stops the process when not cancelled in time. A plain `Thread`, because a deadlocked cooperative pool
/// cannot run the task a Swift Testing time limit would need.
private final class ReadWatchdog: Sendable {
    private let isCancelled = OSAllocatedUnfairLock(initialState: false)

    init(seconds: TimeInterval, message: String) {
        let isCancelled = isCancelled

        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            guard !isCancelled.withLock({ $0 }) else { return }
            fatalError("Deadlock: \(message)")
        }
    }

    func cancel() {
        isCancelled.withLock { $0 = true }
    }
}
