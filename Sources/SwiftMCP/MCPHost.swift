import Foundation
import OSLog

// MARK: - MCPHost Interface

/// The primary interface for interacting with MCP servers
@Observable public final class MCPHost {
  public var connections: [String: ConnectionState] {
    get async { await state.connections }
  }

  // Configuration
  private var configuration: MCPConfiguration
  private let state: MCPHostState

  public init(config: MCPConfiguration = .init()) {
    self.configuration = config
    self.state = MCPHostState()
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

    let state = await client.state
    guard case .running(let sessionInfo) = state else {
      throw MCPError.internalError("Expected running state.  Current state \(state)")
    }

    let connectionState = ConnectionState(
      id: id,
      client: client,
      serverInfo: sessionInfo.serverInfo,
      capabilities: sessionInfo.capabilities
    )

    let task = Task { [weak self] in
      for await notification in client.notifications {
        await self?.handleNotification(notification, for: connectionState)
      }
    }

    await self.state.addConnection(id: id, state: connectionState, task: task)
    return connectionState
  }

  public func disconnect(_ id: String) async {
    guard let state = await self.state.connection(for: id) else { return }
    await state.client.stop()
    await self.state.removeConnection(id: id)
  }

  // MARK: - Capability Management

  /// Find all available tools across connections
  public var availableTools: [MCPTool] {
    get async {
      let connections = await state.connections
      return Array(Set(connections.values.flatMap { $0.tools }))
    }
  }

  /// Find connections supporting specific capabilities
  public func connections(
    supporting feature: ServerCapabilities.Features
  ) async -> [ConnectionState] {
    let connections = await state.connections
    return connections.values.filter { $0.capabilities.supports(feature) }
  }

  // MARK: - Health Monitoring

  /// Get connections that haven't had activity within timeout
  public func inactiveConnections(timeout: TimeInterval) async -> [ConnectionState] {
    let cutoff = Date().addingTimeInterval(-timeout)
    let connections = await state.connections
    return connections.values.filter { $0.lastActivity < cutoff }
  }

  /// Check if any connections are in a failed state
  public var hasFailedConnections: Bool {
    get async {
      let connections = await state.connections
      return connections.values.contains { $0.status == .failed }
    }
  }

  /// Get all failed connections
  public var failedConnections: [ConnectionState] {
    get async {
      let connections = await state.connections
      return connections.values.filter { $0.status == .failed }
    }
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

extension MCPHost {
  actor MCPHostState {
    var connections: [String: ConnectionState] = [:]
    var notificationTasks: [String: Task<Void, Never>] = [:]

    func connection(for id: String) -> ConnectionState? {
      connections[id]
    }

    func addConnection(id: String, state: ConnectionState, task: Task<Void, Never>) {
      connections[id] = state
      notificationTasks[id] = task
    }

    func removeConnection(id: String) {
      connections[id] = nil
      notificationTasks[id] = nil
    }
  }
}
