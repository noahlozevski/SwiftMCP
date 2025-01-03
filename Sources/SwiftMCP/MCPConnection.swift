import Foundation

/// Handle for interacting with a specific MCP server connection
@Observable public final class ConnectionState: Identifiable {
  // MARK: - Properties

  public let id: String
  public let serverInfo: Implementation
  public let capabilities: ServerCapabilities

  public private(set) var tools: [MCPTool] = []
  public private(set) var resources: [MCPResource] = []
  public private(set) var prompts: [MCPPrompt] = []

  public private(set) var lastActivity: Date = Date()
  public private(set) var reconnectCount: Int = 0
  private let connectedAt: Date = Date()

  public private(set) var isRefreshingTools = false
  public private(set) var isRefreshingResources = false
  public private(set) var isRefreshingPrompts = false

  private var statusMonitorTask: Task<Void, Never>?

  let client: MCPClient

  // MARK: - Status

  public private(set) var status: ConnectionStatus = .connected
  public var isConnected: Bool { status == .connected }

  init(
    id: String,
    client: MCPClient,
    serverInfo: Implementation,
    capabilities: ServerCapabilities
  ) {
    self.id = id
    self.client = client
    self.serverInfo = serverInfo
    self.capabilities = capabilities

    self.statusMonitorTask = Task {
      let eventStream = await client.events
      for await event in eventStream {
        switch event {
        case .connectionChanged(let state):
          switch state {
          case .running:
            status = .connected
          case .failed:
            status = .failed
          case .disconnected:
            status = .disconnected
          case .connecting, .initializing:
            status = .connecting
          }
        default:
          continue
        }
      }
    }
  }

  // MARK: - State Management

  public func refresh() async {
    guard isConnected else { return }
    await refreshTools()
    await refreshResources()
    await refreshPrompts()
  }

  func refreshTools() async {
    guard isConnected, capabilities.supports(.tools) else { return }

    isRefreshingTools = true
    defer { isRefreshingTools = false }

    do {
      tools = try await client.listTools().tools
      lastActivity = Date()
    } catch {
      print("Failed to refresh tools: \(error)")
    }
  }

  func refreshResources() async {
    guard isConnected, capabilities.supports(.resources) else { return }

    isRefreshingResources = true
    defer { isRefreshingResources = false }

    do {
      resources = try await client.listResources().resources
      lastActivity = Date()
    } catch {
      print("Failed to refresh resources: \(error)")
    }
  }

  func refreshPrompts() async {
    guard isConnected, capabilities.supports(.prompts) else { return }

    isRefreshingPrompts = true
    defer { isRefreshingPrompts = false }

    do {
      prompts = try await client.listPrompts().prompts
      lastActivity = Date()
    } catch {
      print("Failed to refresh prompts: \(error)")
    }
  }

  // MARK: - Tools API

  public func callTool(
    _ name: String,
    arguments: [String: Any]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> CallToolResult {
    guard isConnected, capabilities.supports(.tools) else {
      throw MCPError.methodNotFound("Connection does not support tools or is disconnected")
    }

    let result = try await client.callTool(name, with: arguments, progress: progress)
    lastActivity = Date()
    return result
  }

  // MARK: - Resources API

  public func readResource(
    _ uri: String,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ReadResourceResult {
    guard isConnected, capabilities.supports(.resources) else {
      throw MCPError.methodNotFound("Connection does not support resources or is disconnected")
    }

    let result = try await client.readResource(uri, progress: progress)
    lastActivity = Date()
    return result
  }

  public func subscribe(to uri: String) async throws {
    guard isConnected, capabilities.supports(.resourceSubscribe) else {
      throw MCPError.methodNotFound(
        "Connection does not support resource subscription or is disconnected")
    }

    try await client.subscribe(to: uri)
    lastActivity = Date()
  }

  public func unsubscribe(from uri: String) async throws {
    guard isConnected, capabilities.supports(.resourceSubscribe) else {
      throw MCPError.methodNotFound(
        "Connection does not support resource subscription or is disconnected")
    }

    try await client.unsubscribe(from: uri)
    lastActivity = Date()
  }

  // MARK: - Prompts API

  public func listPrompts(
    cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ListPromptsResult {
    guard isConnected, capabilities.supports(.prompts) else {
      throw MCPError.methodNotFound("Connection does not support prompts or is disconnected")
    }

    let result = try await client.listPrompts(cursor: cursor, progress: progress)
    lastActivity = Date()
    return result
  }

  public func getPrompt(
    _ name: String,
    arguments: [String: String]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> GetPromptResult {
    guard isConnected, capabilities.supports(.prompts) else {
      throw MCPError.methodNotFound("Connection does not support prompts or is disconnected")
    }

    let result = try await client.getPrompt(name, arguments: arguments, progress: progress)
    lastActivity = Date()
    return result
  }
}

// MARK: - Connection Extensions

extension ConnectionState: Hashable {
  public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// Connection state
public enum ConnectionStatus: Equatable, Sendable {
  case connected
  case connecting
  case disconnected
  case failed

  public static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
    switch (lhs, rhs) {
    case (.connected, .connected),
      (.connecting, .connecting),
      (.disconnected, .disconnected),
      (.failed, .failed):
      return true
    default: return false
    }
  }
}
