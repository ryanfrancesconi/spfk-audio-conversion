
public protocol DeviceAccess: AnyObject {
    var deviceManager: (any AudioDeviceManagerModel)? { get }
}
