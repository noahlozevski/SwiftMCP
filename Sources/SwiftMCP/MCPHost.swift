import Foundation

public struct MCPContext {
  public let id: String
  public let serverInfo: Implementation
  public let capabilities: ServerCapabilities
  public let resources: [MCPResource]
  public let prompts: [MCPPrompt]
  public let tools: [MCPTool]
  public let instructions: String?
}

public struct MCPHostConfiguration {
  /// The default client configuration to use when creating new clients
  public var defaultClientConfig: MCPClient.Configuration

  public init(clientConfig: MCPClient.Configuration) {
    self.defaultClientConfig = clientConfig
  }
}

public protocol MCPContextManaging {
  func handleSampling(_ request: CreateMessageRequest, from client: MCPClient) async throws
    -> CreateMessageResult
}

/// Host should:
/// - Manage "sessions" between clients and servers
/// - Aggregate tools, prompts, resources from sessions
/// - Aggregate notifications from sessions
/// - Hand off sampling requests to the consumer
/// - Enable / Disable Connections
/// - register for notifications
///
///

public actor MCPHost {
  private let configuration: MCPHostConfiguration
  private var contextManager: MCPContextManaging?

  private var notificationTasks: [String: Task<Void, Never>] = [:]

  private struct ServerConnection: Identifiable, Sendable {
    let id: String
    let serverInfo: Implementation
    let capabilities: ServerCapabilities

    let transport: any MCPTransport
    let client: MCPClient

    /// Aggregated capabilities from the server

    var resources: [MCPResource] = []
    var prompts: [MCPPrompt] = []
    var tools: [MCPTool] = []

    /// Initialization instructions, if present, for the host to combine or store.
    var instructions: String?
  }

  private var connections: [String: ServerConnection] = [:]

  public init(configuration: MCPHostConfiguration) {
    self.configuration = configuration
  }

  public var installedServers: [String] {
    connections.keys.map { $0 }
  }

  public func connect(
    _ id: String,
    transport: MCPTransport
  ) async throws {
    let clientConfig = configuration.defaultClientConfig
    let client = MCPClient(
      clientInfo: clientConfig.clientInfo, capabilities: clientConfig.capabilities)

    try await client.start(transport)

    guard case .running(let sessionInfo) = await client.state else {
      throw MCPError.internalError("Expected running state")
    }

    let capabilities = sessionInfo.capabilities

    var prompts: [MCPPrompt] = []
    var tools: [MCPTool] = []
    var resources: [MCPResource] = []

    if capabilities.supports(.prompts) {
      prompts = try await client.listPrompts().prompts
    }

    if capabilities.supports(.resources) {
      resources = try await client.listResources().resources
    }

    if capabilities.supports(.tools) {
      tools = try await client.listTools().tools
    }

    let serverInfo = ServerConnection(
      id: id,
      serverInfo: sessionInfo.serverInfo,
      capabilities: sessionInfo.capabilities,
      transport: transport,
      client: client,
      resources: resources,
      prompts: prompts,
      tools: tools,
      instructions: sessionInfo.instructions
    )

    connections[id] = serverInfo

    await handleNotifications(for: id)
  }

  public func disconnect(_ id: String) async {
    guard let connection = connections.removeValue(forKey: id) else {
      return
    }

    await unregisterNotifications(for: id)
    await connection.client.stop()
  }

  public func getContext(for id: String) async throws -> MCPContext {
    guard let connection = connections[id] else {
      throw MCPError.invalidRequest("No connection found for \(id)")
    }

    return MCPContext(
      id: id,
      serverInfo: connection.serverInfo,
      capabilities: connection.capabilities,
      resources: connection.resources,
      prompts: connection.prompts,
      tools: connection.tools,
      instructions: connection.instructions
    )
  }

  public func availableTools() -> [MCPTool] {
    connections.values.flatMap { $0.tools }
  }

  public func client(id: String) -> MCPClient? {
    guard let connection = connections[id] else { return nil }

    return connection.client
  }

  // MARK: - Private Helpers

  private func handleNotifications(for id: String) async {
    guard let connection = connections[id] else { return }

    notificationTasks[id] = Task {
      for await notification in connection.client.notifications {
        await processNotification(notification, for: id)
      }
    }
  }

  private func processNotification(_ notification: MCPNotification, for id: String) async {
    guard var connection = connections[id] else { return }

    switch notification {
    case is ResourceListChangedNotification:
      if let resources = try? await connection.client.listResources() {
        connection.resources = resources.resources
      }

    case is PromptListChangedNotification:
      if let prompts = try? await connection.client.listPrompts() {
        connection.prompts = prompts.prompts
      }

    case is ToolListChangedNotification:
      if let tools = try? await connection.client.listTools() {
        connection.tools = tools.tools
      }

    default:
      break
    }
  }

  private func unregisterNotifications(for id: String) async {
    guard let task = notificationTasks.removeValue(forKey: id) else { return }
    task.cancel()
  }
}
