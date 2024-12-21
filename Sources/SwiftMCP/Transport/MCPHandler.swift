import Foundation

/// A type that can handle any MCP response
protocol ResponseHandler {
  /// Handle a raw response message
  func handle(_ data: Data) throws -> Bool

  /// Cancel the pending response with an error
  func cancel(_ error: Error)
}

/// Type-safe response handler for a specific request type
final class TypedResponseHandler<Request: MCPRequest>: ResponseHandler {
  /// The continuation waiting for the response
  private let continuation: CheckedContinuation<Request.Response, Error>

  init(continuation: CheckedContinuation<Request.Response, Error>) {
    self.continuation = continuation
  }

  func handle(_ data: Data) throws -> Bool {
    guard
      let response = try? JSONDecoder().decode(
        JSONRPCMessage<Request>.self,
        from: data
      )
    else {
      return false
    }

    switch response {
    case .response(_, let result):
      continuation.resume(returning: result)
      return true
    case .error(_, let error):
      continuation.resume(throwing: error)
      return true
    default:
      return false
    }
  }

  func cancel(_ error: Error) {
    continuation.resume(throwing: error)
  }
}
