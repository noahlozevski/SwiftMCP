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
    func stop() async

    /// Send data with optional timeout
    func send(_ data: Data, timeout: TimeInterval?) async throws
}

extension MCPTransport {
    // Default timeout implementation using our with(timeout:) utility
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
