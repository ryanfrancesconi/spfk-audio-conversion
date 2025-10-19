// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import AVFoundation
import Foundation
@testable import SPFKAudio
import SPFKTesting
import SPFKUtils
import Testing

@Suite(.serialized, .tags(.realtime))
final class MutiFormatPlayerTests: AudioWorkspaceTestCase {
    @Test func playerTime() async throws {
        try await setup()
    }
}
