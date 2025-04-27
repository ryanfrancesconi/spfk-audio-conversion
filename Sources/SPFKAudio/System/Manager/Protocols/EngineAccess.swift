
public protocol EngineAccess: AnyObject {
    var engineManager: (any AudioEngineManagerModel)? { get }
}
