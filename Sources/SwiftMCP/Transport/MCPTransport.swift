import Foundation

/// Protocol defining a MCP transport implementation
public protocol MCPTransport: Actor {
  /// Current state of the transport
  var state: TransportState { get }
  
  /// Transport configuration
  var configuration: TransportConfiguration { get }
  
  /// Creates an async stream of messages from this transport
  /// If the transport is not started, it will be started automatically
  func messages() -> AsyncThrowingStream<Data, Error>
  
  /// Start the transport
  func start() async throws
  
  /// Stop the transport
  func stop()
  
  /// Send data with optional timeout
  func send(_ data: Data, timeout: TimeInterval?) async throws
}

extension MCPTransport {
  public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    if data.count > configuration.maxMessageSize {
      throw TransportError.messageTooLarge(data.count)
    }
    
    let timeout = timeout ?? configuration.sendTimeout
    try await with(timeout: .microseconds(Int64(timeout * 1_000_000))) { [weak self] in
      try await self?.send(data, timeout: nil)
    }
  }
}

/// Core transport errors
public enum TransportError: Error, CustomStringConvertible {
  /// Timeout waiting for operation
  case timeout(operation: String)
  
  /// Invalid message format
  case invalidMessage(String)
  
  /// Connection failed
  case connectionFailed(Error)
  
  /// Operation failed
  case operationFailed(Error)
  
  /// Transport is in wrong state for operation
  case invalidState(String)
  
  /// Message exceeds size limit
  case messageTooLarge(Int)
  
  /// Transport not supported on the target platform
  case notSupported(String)
  
  public var description: String {
    switch self {
    case .timeout(let operation):
      return "Timeout waiting for operation: \(operation)"
    case .invalidMessage(let message):
      return "Invalid message format: \(message)"
    case .connectionFailed(let error):
      return "Connection failed: \(error)"
    case .operationFailed(let error):
      return "Operation failed: \(error)"
    case .invalidState(let message):
      return "Invalid state: \(message)"
    case .messageTooLarge(let size):
      return "Message exceeds size limit: \(size)"
    case .notSupported(let message):
      return "Transport type not supported: \(message)"
    }
  }
}
