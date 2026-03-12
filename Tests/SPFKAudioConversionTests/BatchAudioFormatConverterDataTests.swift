// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import Foundation
import SPFKAudioBase
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct BatchAudioFormatConverterDataTests {
    private func makeSources(count: Int) -> [AudioFormatConverterSource] {
        (0 ..< count).map { i in
            AudioFormatConverterSource(
                input: URL(fileURLWithPath: "/input_\(i).wav"),
                output: URL(fileURLWithPath: "/output_\(i).m4a"),
                options: AudioFormatConverterOptions(format: .m4a)
            )
        }
    }

    // MARK: - Initial state

    @Test func emptyInitHasZeroCounts() async {
        let data = BatchAudioFormatConverterData()
        let count = await data.count
        let completed = await data.completed
        let batchSize = await data.batchSize
        let percent = await data.percent

        #expect(count == 0)
        #expect(completed == 0)
        #expect(batchSize == 0)
        #expect(percent == 0)
    }

    // MARK: - update(sources:)

    @Test func updateSetsSources() async {
        let data = BatchAudioFormatConverterData()
        let sources = makeSources(count: 5)
        await data.update(sources: sources)

        let count = await data.count
        let batchSize = await data.batchSize
        let completed = await data.completed

        #expect(count == 5)
        #expect(batchSize == 5)
        #expect(completed == 0)
    }

    @Test func updateResetsCompletedCount() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: makeSources(count: 3))
        await data.increment()
        await data.increment()

        // Reset
        await data.update(sources: makeSources(count: 2))

        let completed = await data.completed
        #expect(completed == 0)
    }

    // MARK: - batchSize clamping

    @Test func batchSizeClampedTo8() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: makeSources(count: 20))

        let batchSize = await data.batchSize
        #expect(batchSize == 8)
    }

    @Test func batchSizeMatchesCountWhenSmall() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: makeSources(count: 3))

        let batchSize = await data.batchSize
        #expect(batchSize == 3)
    }

    @Test func batchSizeIsZeroForEmptySources() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: [])

        let batchSize = await data.batchSize
        #expect(batchSize == 0)
    }

    // MARK: - increment and percent

    @Test func incrementAdvancesCompletedCount() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: makeSources(count: 4))

        await data.increment()
        let completed = await data.completed
        #expect(completed == 1)
    }

    @Test func percentTracksProgress() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: makeSources(count: 4))

        await data.increment()
        await data.increment()

        let percent = await data.percent
        #expect(percent == 0.5)
    }

    @Test func percentIsOneWhenAllComplete() async {
        let data = BatchAudioFormatConverterData()
        await data.update(sources: makeSources(count: 2))

        await data.increment()
        await data.increment()

        let percent = await data.percent
        #expect(percent == 1.0)
    }

    @Test func percentIsZeroForEmptyData() async {
        let data = BatchAudioFormatConverterData()
        let percent = await data.percent
        #expect(percent == 0)
    }

    // MARK: - init(sources:)

    @Test func initWithSourcesSetsState() async {
        let sources = makeSources(count: 6)
        let data = await BatchAudioFormatConverterData(sources: sources)

        let count = await data.count
        let batchSize = await data.batchSize

        #expect(count == 6)
        #expect(batchSize == 6)
    }
}
