// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

import AudioToolbox

public protocol Mixable {
    var volume: AUValue { get set }
    var pan: AUValue { get set }
    var isBypassed: Bool { get set }
}
