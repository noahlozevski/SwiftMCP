import Foundation
import OSLog

public enum RootSource {
  /// A static list of roots
  case list([Root])

  /// A dynamic list of roots
  case dynamic(() -> [Root])
}

/// Configuration for filesystem roots
public struct RootsConfig {
  let source: RootSource
  let autoUpdate: Bool

  public static func list(_ roots: [Root]) -> Self {
    .init(source: .list(roots), autoUpdate: false)
  }

  public static func dynamic(_ roots: @escaping () -> [Root]) -> Self {
    .init(source: .dynamic(roots), autoUpdate: true)
  }

  var roots: [Root] {
    switch source {
    case .list(let roots): return roots
    case .dynamic(let roots): return roots()
    }
  }
}

/// Configuration for AI model sampling
public struct SamplingConfig {
  /// Handler for sampling requests
  public let handler: @Sendable (CreateMessageRequest) async throws -> CreateMessageResult

  public init(
    handler: @escaping @Sendable (CreateMessageRequest) async throws -> CreateMessageResult
  ) {
    self.handler = handler
  }
}

public struct MCPConfiguration {
  /// Broadcasted capabilities for all clients
  public internal(set) var capabilities: ClientCapabilities

  public var clientInfo: Implementation
  /// Configuration for filesystem roots
  public var roots: RootsConfig?

  /// Configuration for AI model sampling
  public var sampling: SamplingConfig?

  var clientConfig: MCPClient.Configuration {
    MCPClient.Configuration(
      clientInfo: clientInfo,
      capabilities: capabilities
    )
  }

  public init(
    roots: RootsConfig? = nil,
    sampling: SamplingConfig? = nil,
    clientInfo: Implementation = .defaultClient,
    capabilities: ClientCapabilities = .init()
  ) {
    self.roots = roots
    self.sampling = sampling
    self.capabilities = capabilities
    self.clientInfo = clientInfo

    if roots != nil {
      self.capabilities.roots = .init(listChanged: true)
    }

    if sampling != nil, !capabilities.supports(.sampling) {
      self.capabilities.sampling = .init()
    }

    self.capabilities = capabilities
  }
}

// MARK: - MCPHost Interface

/// The primary interface for interacting with MCP servers
public actor MCPHost {
  private var configuration: MCPConfiguration
  private var connections: [String: ServerConnection] = [:]
  private var notificationTasks: [String: Task<Void, Never>] = [:]

  /// Initialize an MCP host with the given configuration
  public init(config: MCPConfiguration = .init()) {
    self.configuration = config
  }

  /// Connect to an MCP server using the provided transport
  @discardableResult
  public func connect(
    _ id: String,
    transport: MCPTransport
  ) async throws -> MCPConnection {
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

    let connection = MCPConnection(
      id: id,
      client: client,
      serverInfo: sessionInfo.serverInfo,
      capabilities: sessionInfo.capabilities
    )

    // Start notification handling
    notificationTasks[id] = Task { [weak self] in
      for await notification in client.notifications {
        await self?.handleNotification(notification, for: id)
      }
    }

    connections[id] = ServerConnection(connection: connection)

    return connection
  }

  public func disconnect(_ id: MCPConnection.ID) async {
    guard let connection = connections[id] else { return }

    await connection.connection.disconnect()
    connections[id] = nil
    notificationTasks[id] = nil
  }

  public func disconnect(_ connection: MCPConnection) async {
    await disconnect(connection.id)
  }

  /// Get all active connections
  public var activeConnections: [MCPConnection] {
    get async {
      Array(connections.values.map { $0.connection })
    }
  }

  /// Get a specific connection by ID
  public func connection(id: MCPConnection.ID) async -> MCPConnection? {
    connections[id]?.connection
  }

  /// Update the roots configuration
  public func updateRoots(_ config: RootsConfig?) async {
    configuration.roots = config

    if config != nil {
      configuration.capabilities.roots = .init(listChanged: true)
    } else {
      configuration.capabilities.roots = nil
    }

    await withTaskGroup(of: Void.self) { group in
      for connection in connections.values {
        group.addTask {
          try? await connection.connection.updateRoots(config)
        }
      }
    }
  }

  /// Update the sampling configuration
  public func updateSampling(_ config: SamplingConfig?) async {
    configuration.sampling = config
    // Update existing connections
  }

  // MARK: - Private

  private struct ServerConnection {
    let connection: MCPConnection
    var resources: [MCPResource] = []
    var prompts: [MCPPrompt] = []
    var tools: [MCPTool] = []
  }

  private func handleNotification(
    _ notification: any MCPNotification,
    for id: MCPConnection.ID
  ) async {
    guard var serverConnection = connections[id] else { return }

    let connection = serverConnection.connection
    switch notification {
    case is ToolListChangedNotification:
      let toolState = await connection.tools
      await toolState.refresh()
      serverConnection.tools = toolState.tools
    case is ResourceListChangedNotification:
      let resourceState = await connection.resources
      await resourceState.refresh()
      serverConnection.resources = resourceState.resources
    case is PromptListChangedNotification:
      let promptState = await connection.prompts
      await promptState.refresh()
      serverConnection.prompts = promptState.prompts
    case let resourceUpdate as ResourceUpdatedNotification:
      let resourceState = await connection.resources
      // TODO: broadcast uri update?
      await resourceState.refresh()
      serverConnection.resources = resourceState.resources
    default:
      break
    }

    connections[id] = serverConnection
  }
}
