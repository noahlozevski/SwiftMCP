import Foundation

/// Protocol defining common behavior for MCP endpoints
public protocol MCPEndpointProtocol: Actor {
  associatedtype SessionInfo: Equatable

  /// Current endpoint state
  var state: MCPEndpointState<SessionInfo> { get }

  /// Stream of notifications from this endpoint
  var notifications: AsyncStream<MCPNotification> { get }

  /// Start the endpoint with the given transport
  func start(_ transport: MCPTransport) async throws

  /// Stop the endpoint
  func stop() async

  /// Send a request and await response
  func send<R: MCPRequest>(_ request: R) async throws -> R.Response
}

/// Common state representation for MCP endpoints
public enum MCPEndpointState<State: Equatable>: Equatable {
  /// Endpoint is disconnected
  case disconnected

  /// Endpoint is connecting
  case connecting

  /// Endpoint is performing initialization
  case initializing

  /// Endpoint is running with negotiated capabilities
  case running(State)

  /// Endpoint has failed
  case failed(Error)

  public static func == (lhs: MCPEndpointState, rhs: MCPEndpointState) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected),
      (.connecting, .connecting),
      (.initializing, .initializing):
      return true
    case (.running(let lCap), .running(let rCap)):
      return lCap == rCap
    case (.failed, .failed):
      // Don't compare errors, just that both are failed
      return true
    default:
      return false
    }
  }
}
