// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

import Foundation

public protocol Effectable: AnyObject {
    var audioUnitChain: AudioUnitChain { get }
}
