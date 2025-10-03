// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.tags(.file))
class WaveformDataRequestTests: BinTestCase {
    @Test func getData() async throws {
        let input = BundleResources.shared.tabla_6_channel
        let data = try await WaveformDataRequest.parse(url: input, resolution: .low, priority: .low)

        // channel count for the file
        #expect(data.count == 6)

        for channel in data {
            #expect(channel.count == 1315)
        }
    }

    @Test func shouldError() async throws {
        let input = BundleResources.shared.no_data_chunk

        await #expect(throws: (any Error).self) {
            do {
                _ = try await WaveformDataRequest.parse(url: input, resolution: .low)
            } catch {
                Log.error(error)

                #expect(
                    error.localizedDescription.contains("No audio was found")
                )

                throw error
            }
        }
    }
}
