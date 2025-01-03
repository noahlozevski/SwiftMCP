import Foundation
import OSLog

// MARK: - MCPHost Interface

/// The primary interface for interacting with MCP servers
@Observable public final class MCPHost {
  // Public state
  public private(set) var connections: [String: ConnectionState] = [:]

  // Configuration
  private var configuration: MCPConfiguration
  private var notificationTasks: [String: Task<Void, Never>] = [:]

  public init(config: MCPConfiguration = .init()) {
    self.configuration = config
  }

  // MARK: - Connection Management

  @discardableResult
  public func connect(
    _ id: String,
    transport: MCPTransport
  ) async throws -> ConnectionState {
    let client = MCPClient(configuration: configuration.clientConfig)

    if let sampling = configuration.sampling {
      await client.registerHandler(for: CreateMessageRequest.self) { request in
        try await sampling.handler(request)
      }
    }

    try await client.start(transport)

    guard case .running(let sessionInfo) = await client.state else {
      throw MCPError.internalError("Expected running state")
    }

    let state = ConnectionState(
      id: id,
      client: client,
      serverInfo: sessionInfo.serverInfo,
      capabilities: sessionInfo.capabilities
    )

    notificationTasks[id] = Task { [weak self] in
      for await notification in client.notifications {
        await self?.handleNotification(notification, for: state)
      }
    }

    connections[id] = state
    return state
  }

  public func disconnect(_ id: String) async {
    guard let state = connections[id] else { return }
    await state.client.stop()
    connections[id] = nil
    notificationTasks[id] = nil
  }

  // MARK: - Capability Management

  /// Find all available tools across connections
  public var availableTools: [MCPTool] {
    Array(Set(connections.values.flatMap { $0.tools }))
  }

  /// Find connections supporting specific capabilities
  public func connections(supporting feature: ServerCapabilities.Features) -> [ConnectionState] {
    connections.values.filter { $0.capabilities.supports(feature) }
  }

  // MARK: - Health Monitoring

  /// Get connections that haven't had activity within timeout
  public func inactiveConnections(timeout: TimeInterval) -> [ConnectionState] {
    let cutoff = Date().addingTimeInterval(-timeout)
    return connections.values.filter { $0.lastActivity < cutoff }
  }

  /// Check if any connections are in a failed state
  public var hasFailedConnections: Bool {
    connections.values.contains { $0.status == .failed }
  }

  /// Get all failed connections
  public var failedConnections: [ConnectionState] {
    connections.values.filter { $0.status == .failed }
  }

  // MARK: - Private

  private func handleNotification(
    _ notification: any MCPNotification,
    for state: ConnectionState
  ) async {
    switch notification {
    case is ToolListChangedNotification:
      await state.refreshTools()
    case is ResourceListChangedNotification:
      await state.refreshResources()
    case is PromptListChangedNotification:
      await state.refreshPrompts()
    case is ResourceUpdatedNotification:
      await state.refreshResources()
    default:
      break
    }
  }
}
