import Foundation

/// Handles request/response correlation with type safety.
///
/// An actor that stores pending requests and resumes them when responses arrive.
public actor MessageCoordinator<Request: MCPRequest> {
    private var pendingRequests: [RequestID: CheckedContinuation<Request.Response, Error>] = [:]

    public init() {}

    /// Wait for a response to a specific request ID.
    public func waitForResponse(id: RequestID) async throws -> Request.Response {
        try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    /// Handle an incoming response message and resume the continuation.
    public func handleResponse(_ response: JSONRPCMessage<Request, Request.Response>) {
        switch response {
        case .response(let id, let resp):
            pendingRequests[id]?.resume(returning: resp)
            pendingRequests[id] = nil
        case .error(let id, let err):
            pendingRequests[id]?.resume(throwing: err)
            pendingRequests[id] = nil
        default:
            break
        }
    }

    /// Cancel a pending request with a given reason.
    public func cancelRequest(_ id: RequestID, reason: String? = nil) {
        let error = MCPError.connectionClosed(reason: reason)
        pendingRequests[id]?.resume(throwing: error)
        pendingRequests[id] = nil
    }
}
