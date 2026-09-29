// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKAudioBase
import SPFKBase
import SPFKMetadata
import SPFKMetadataBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
final class WriteMarkersPCMTests: BinTestCase {
    private let color = HexColor(string: "0000FFFF")

    private static let fixtures: [(URL, AudioFileType)] = [
        (TestBundleResources.shared.tabla_wav, .wav),
        (TestBundleResources.shared.tabla_aif, .aiff),
    ]

    private func roundTrip(
        _ marker: AudioMarkerDescription,
        fixture: URL,
        type: AudioFileType
    ) async throws -> AudioMarkerDescription {
        let url = try copyToBin(url: fixture)
        AudioFormatConverter.writeMarkers([marker], to: url, outputType: type)

        let collection = try await AudioMarkerDescriptionCollection(url: url, fileType: type)
        #expect(collection.markerDescriptions.count == 1)
        return try #require(collection.markerDescriptions.first)
    }

    @Test(arguments: fixtures)
    func colorAndRegionSurvive(fixture: URL, type: AudioFileType) async throws {
        let marker = AudioMarkerDescription(
            name: "Verse", startTime: 1, endTime: 3.5, sampleRate: 48000,
            hexColor: color, markerType: .region
        )
        let read = try await roundTrip(marker, fixture: fixture, type: type)

        #expect(read.name == "Verse")
        #expect(read.hexColor == color)
        #expect(read.markerType == .region)
        #expect(read.endTime.map { abs($0 - 3.5) < 0.001 } == true)
    }

    /// A marker read from a chapter format carries no sample rate.
    @Test(arguments: fixtures)
    func markerWithoutSampleRateKeepsPosition(fixture: URL, type: AudioFileType) async throws {
        let marker = AudioMarkerDescription(name: "Chapter", startTime: 1)
        let read = try await roundTrip(marker, fixture: fixture, type: type)

        #expect(abs(read.startTime - 1) < 0.001)
    }

    @Test func longAIFFNameKeepsColor() async throws {
        let longName = String(repeating: "x", count: 300)
        let marker = AudioMarkerDescription(name: longName, startTime: 1, sampleRate: 48000, hexColor: color)
        let read = try await roundTrip(marker, fixture: TestBundleResources.shared.tabla_aif, type: .aiff)

        #expect(read.hexColor == color)
        #expect(read.name.map { longName.hasPrefix($0) && $0.isNotEmpty } == true)
    }
}
