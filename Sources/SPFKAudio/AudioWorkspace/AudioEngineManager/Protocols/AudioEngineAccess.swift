// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

public protocol AudioEngineAccess: AnyObject {
    var audioEngineAccess: (any AudioEngineManagerModel)? { get }
}
