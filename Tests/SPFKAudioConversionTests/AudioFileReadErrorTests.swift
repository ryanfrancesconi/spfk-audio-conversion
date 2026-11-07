// Copyright Ryan Francesconi. All Rights Reserved.

import AVFoundation
import Foundation
import SPFKAudioBase
import SPFKTesting
import Testing

@testable import SPFKAudioConversion

@Suite(.tags(.file))
struct AudioFileReadErrorTests {
    @Test("a failed open names the file")
    func openFailureNamesFile() {
        let url = URL(fileURLWithPath: "/nonexistent/missing.wav")

        #expect {
            _ = try AVAudioFilePCMSource(url: url)
        } throws: { error in
            guard case AudioFileReadError.openFailed? = error as? AudioFileReadError else { return false }
            return error.localizedDescription.hasPrefix("missing.wav could not be opened (")
        }
    }
}
