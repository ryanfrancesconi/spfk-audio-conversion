
public protocol AudioDeviceAccess: AnyObject {
    var audioDeviceAccess: (any AudioDeviceManagerModel)? { get }
}
