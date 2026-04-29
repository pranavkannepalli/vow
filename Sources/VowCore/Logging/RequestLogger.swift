import Foundation

public protocol RequestLifecycleLogger {
    func log(_ event: String, requestID: UUID, metadata: [String: String]?)
}

public struct NoopRequestLifecycleLogger: RequestLifecycleLogger {
    public init() {}
    public func log(_ event: String, requestID: UUID, metadata: [String : String]?) {}
}
