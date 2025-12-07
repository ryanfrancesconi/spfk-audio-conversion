// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

public protocol AudioDeviceAccess: AnyObject {
    var audioDeviceAccess: (any AudioDeviceManagerModel)? { get }
}
