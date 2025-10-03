// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

public protocol EngineAccess: AnyObject {
    func engineAccess() -> (any AudioEngineManagerModel)?
}
