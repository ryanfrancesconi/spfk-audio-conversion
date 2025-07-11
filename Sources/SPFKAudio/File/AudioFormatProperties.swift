// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKMetadata

import AVFoundation
import Foundation

public struct AudioFormatProperties: Hashable, Codable {
    public var channelCount: AVAudioChannelCount
    
    public var sampleRate: Double
    
    public var bitsPerChannel: Int?
    
    public var duration: TimeInterval = 0
    
}
