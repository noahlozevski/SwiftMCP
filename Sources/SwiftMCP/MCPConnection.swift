import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "MCPConnection")

/// Information about a connected MCP server
public struct ConnectionInfo: Sendable, Identifiable {
  /// Unique connection identifier
  public let id: String

  /// Current connection state
  public let state: ConnectionState

  /// Server information
  public let serverInfo: Implementation

  /// Server capabilities
  public let capabilities: ServerCapabilities

  /// Connection statistics
  public let stats: ConnectionStats

  public struct ConnectionStats: Sendable {
    public let lastActivity: Date
    public let reconnectCount: Int
    public let connectedAt: Date
  }
}

/// Handle for interacting with a specific MCP server connection
public actor MCPConnection: Identifiable, Sendable {
  public let id: String
  private let client: MCPClient
  private let serverInfo: Implementation
  private let capabilities: ServerCapabilities

  private var lastActivity: Date = Date()
  private var reconnectCount: Int = 0
  private var connectedAt: Date = Date()
  private var state: ConnectionState = .connected

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
  }

  /// Get current connection information
  public var info: ConnectionInfo {
    ConnectionInfo(
      id: id,
      state: state,
      serverInfo: serverInfo,
      capabilities: capabilities,
      stats: .init(
        lastActivity: lastActivity,
        reconnectCount: reconnectCount,
        connectedAt: connectedAt
      )
    )
  }

  /// Check if connection is active
  public var isConnected: Bool {
    get async {
      let isConnected = await client.isConnected
      return isConnected
    }
  }

  internal func disconnect() async {
    state = .disconnecting
    await client.stop()
    state = .disconnected
  }

  internal func reconnect() async throws {
    try await client.reconnect()
  }

  // MARK: - Feature APIs

  public lazy var tools = ToolState(connection: self)

  public lazy var resources = ResourceState(connection: self)

  public lazy var prompts = PromptState(connection: self)

  public lazy var roots = RootsState(connection: self)

  public struct RefreshOptions: OptionSet {
    public let rawValue: Int

    public static let tools = RefreshOptions(rawValue: 1 << 0)
    public static let resources = RefreshOptions(rawValue: 1 << 1)
    public static let prompts = RefreshOptions(rawValue: 1 << 2)

    public static let all: RefreshOptions = [.tools, .resources, .prompts]

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }

  public func fetch(_ options: RefreshOptions = .all) async {
    if options.contains(.tools) {
      await tools.refresh()
    }
    if options.contains(.resources) {
      await resources.refresh()
    }
    if options.contains(.prompts) {
      await prompts.refresh()
    }
  }

  // MARK: - Implementation Details

  internal func listTools() async throws -> [MCPTool] {
    try await client.listTools().tools
  }

  internal func callTool(
    _ name: String,
    arguments: [String: Any]?,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> CallToolResult {
    try await client.callTool(name, with: arguments, progress: progress)
  }

  internal func listResources() async throws -> [MCPResource] {
    try await client.listResources().resources
  }

  internal func readResource(
    _ uri: String,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ReadResourceResult {
    try await client.readResource(uri, progress: progress)
  }

  internal func subscribe(to uri: String) async throws {
    try await client.subscribe(to: uri)
  }

  internal func unsubscribe(from uri: String) async throws {
    try await client.unsubscribe(from: uri)
  }

  internal func listPrompts() async throws -> [MCPPrompt] {
    try await client.listPrompts().prompts
  }

  internal func getPrompt(
    _ name: String,
    arguments: [String: String]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> GetPromptResult {
    try await client.getPrompt(name, arguments: arguments ?? [:])
  }

  internal func updateRoots(
    _ config: RootsConfig?
  ) async throws {
    try await client.updateRoots(config?.roots)
  }

  // MARK: - Notifications

  public func notifications() -> AsyncStream<any MCPNotification> {
    client.notifications
  }

  public func emit(_ notification: any MCPNotification) async throws {
    try await client.emit(notification)
  }
}

// Connection state
public enum ConnectionState: Equatable, Sendable {
  case connected
  case connecting
  case disconnecting
  case disconnected
  case failed(Error)

  public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
    switch (lhs, rhs) {
    case (.connected, .connected),
      (.connecting, .connecting),
      (.disconnecting, .disconnecting),
      (.disconnected, .disconnected):
      return true
    case (.failed, .failed): return true
    default: return false
    }
  }
}
