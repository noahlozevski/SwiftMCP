import Foundation
import Testing

@testable import SwiftMCP

@Suite("MCP Hosts", .serialized)
struct MCPHostTests {
  var configuration = MCPConfiguration(
    roots: .list([])
  )

  var everythingTransport: MCPTransport {
    StdioTransport(
      command: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"]
    )
  }

  var memoryTransport: MCPTransport {
    StdioTransport(
      command: "npx", arguments: ["-y", "@modelcontextprotocol/server-memory"])
  }

  @Test
  func testHostConnection() async throws {
    let host = MCPHost(config: configuration)

    let connection = try await host.connect("memory", transport: memoryTransport)

    await connection.refresh()
    let tools = connection.tools

    #expect(tools.count > 0)

    await host.disconnect(connection.id)
    try await Task.sleep(for: .milliseconds(50))

    let isConnected = connection.isConnected

    #expect(!isConnected)
  }

  @Test
  func testTools() async throws {
    let host = MCPHost(config: configuration)

    let connection = try await host.connect("everything", transport: everythingTransport)

    await connection.refreshTools()

    let tools = connection.tools

    #expect(tools.count > 0)

    let echoResponse = try await connection.callTool(
      "echo", arguments: ["message": "Hello, World!"])
    let echoContent = try #require(echoResponse.content.first)
    guard case let .text(echoMessage) = echoContent else {
      Issue.record("Expected string content for echo tool")
      return
    }

    #expect(echoMessage.text == "Echo: Hello, World!")

    let addResponse = try await connection.callTool("add", arguments: ["a": 1, "b": 2])
    let addContent = try #require(addResponse.content.first)
    guard case let .text(addResult) = addContent else {
      Issue.record("Expected string content for add tool")
      return
    }

    #expect(addResult.text.contains("3"))

    // Image
    let imageResponse = try await connection.callTool("getTinyImage", arguments: [:])

    let imageContent = imageResponse.content.first { content in
      guard case .image = content else {
        return false
      }

      return true
    }

    guard case let .image(imageMessage) = imageContent else {
      Issue.record("Expected binary content for image tool")
      return
    }

    #expect(imageMessage.data.count > 0)
  }

  @Test
  func testToolsWithProgress() async throws {
    let host = MCPHost(config: configuration)

    let connection = try await host.connect("everything", transport: everythingTransport)

    await connection.refreshTools()
    let tools = connection.tools

    #expect(tools.count > 0)

    var progressCalled = false

    _ = try await connection.callTool(
      "longRunningOperation",
      arguments: [
        "duration": 5,
        "step": 10,
      ]
    ) {
      (_, _) in

      progressCalled = true
    }

    try await Task.sleep(for: .seconds(5))
    #expect(progressCalled)
  }

  @Test
  func testSampling() async throws {
    let config = MCPConfiguration(
      roots: .list([]),
      sampling: .init(handler: { _ in
        return .init(
          _meta: nil, content: .text(.init(text: "Hello", annotations: nil)), model: "",
          role: .user, stopReason: "")
      })
    )
    let host = MCPHost(config: config)

    let connection = try await host.connect("everything", transport: everythingTransport)

    let sampleResponse = try await connection.callTool(
      "sampleLLM", arguments: ["prompt": "Hello, World!"])
    print(sampleResponse)
    #expect(sampleResponse.content.count > 0)
  }

  @Test
  func testEverythingServerResources() async throws {
    let host = MCPHost()

    let connection = try await host.connect("test", transport: everythingTransport)

    await connection.refreshResources()

    #expect(connection.resources.count > 0)

    let textResource = try await connection.readResource("test://static/resource/1")
    #expect(textResource.contents.count > 0)

    let binaryResource = try await connection.readResource("test://static/resource/2")
    #expect(binaryResource.contents.count > 0)
  }

  @Test
  func testPrompts() async throws {
    let host = MCPHost()

    let connection = try await host.connect("test", transport: everythingTransport)

    await connection.refreshPrompts()

    let simplePrompt = try await connection.getPrompt("simple_prompt")
    #expect(simplePrompt.messages.count > 0)

    let complexPrompt = try await connection.getPrompt(
      "complex_prompt",
      arguments: ["temperature": "1"]
    )
    #expect(complexPrompt.messages.count > 0)

    print(complexPrompt)
    print(simplePrompt)
  }

  @Test("Host manages connection state")
  func testConnectionStateManagement() async throws {
    let host = MCPHost()

    // Initial state
    var connections = await host.connections
    #expect(connections.isEmpty)

    // Connect
    let connection = try await host.connect("test", transport: everythingTransport)
    connections = await host.connections
    #expect(connections.count == 1)
    #expect(connections["test"]?.id == "test")
    #expect(connection.status == .connected)
    #expect(connection.isConnected)

    // Verify initial feature state
    #expect(connection.tools.isEmpty)
    #expect(connection.resources.isEmpty)
    #expect(connection.prompts.isEmpty)
    #expect(!connection.isRefreshingTools)
    #expect(!connection.isRefreshingResources)
    #expect(!connection.isRefreshingPrompts)

    // Refresh should populate features
    await connection.refresh()
    #expect(!connection.tools.isEmpty)
    #expect(!connection.resources.isEmpty)
    #expect(!connection.prompts.isEmpty)

    // Disconnect
    await host.disconnect(connection.id)
    connections = await host.connections
    #expect(connections.isEmpty)
    try await Task.sleep(for: .milliseconds(50))
    #expect(!connection.isConnected)
    #expect(connection.status == .disconnected)
  }

  @Test("Host aggregates tools across connections")
  func testToolAggregation() async throws {
    let host = MCPHost()

    // Connect multiple servers
    let conn1 = try await host.connect("test1", transport: everythingTransport)
    let conn2 = try await host.connect("test2", transport: memoryTransport)

    async let task1 = conn1.refresh()
    async let task2 = conn2.refresh()

    let (_, _) = await (task1, task2)

    // Should aggregate all unique tools
    var allTools = await host.availableTools
    #expect(allTools.count > 0)
    #expect(allTools.count >= conn1.tools.count)
    #expect(allTools.count >= conn2.tools.count)

    // Tool list should update when connections refresh
    let initialCount = allTools.count
    await conn1.refreshTools()
    allTools = await host.availableTools
    #expect(allTools.count >= initialCount)
  }

  @Test("Host handles feature notifications")
  func testFeatureNotifications() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingTransport)

    // Initial refresh
    await connection.refresh()
    let initialTools = connection.tools

    // Simulate tool list change notification
    try await connection.client.emit(ToolListChangedNotification())
    try await Task.sleep(for: .seconds(1))

    // Connection state should be updated
    #expect(connection.tools.count >= initialTools.count)

    // Similar tests for resources and prompts
    let initialResources = connection.resources
    try await connection.client.emit(ResourceListChangedNotification())
    try await Task.sleep(for: .seconds(1))
    #expect(connection.resources.count >= initialResources.count)
  }

  @Test("Host manages progress updates")
  func testProgressHandling() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingTransport)

    await connection.refreshTools()
    var progressUpdates: [(Double, Double?)] = []

    // Long running operation with progress
    _ = try await connection.callTool(
      "longRunningOperation",
      arguments: ["duration": 2, "steps": 4],
      progress: { progress, total in
        progressUpdates.append((progress, total))
      }
    )

    #expect(!progressUpdates.isEmpty)
    #expect(progressUpdates.count >= 4)
  }

  @Test("Host handles connection errors")
  func testConnectionErrorHandling() async throws {
    let host = MCPHost()

    // Bad transport that will fail
    let badTransport = StdioTransport(
      command: "invalid-command",
      arguments: []
    )

    do {
      _ = try await host.connect("test", transport: badTransport)
      Issue.record("Expected connection to fail")
    } catch {
      #expect(true)
      let connections = await host.connections
      #expect(connections.isEmpty)
    }

    // Test automatic state updates on connection failure
    let connection = try await host.connect("test", transport: everythingTransport)
    await connection.refresh()

    // Force connection failure
    await connection.client.stop()
    try await Task.sleep(for: .seconds(1))

    #expect(connection.status == .disconnected)
    #expect(!connection.isConnected)
    #expect((await host.failedConnections).isEmpty)
  }

  @Test("Host handles client capability checks")
  func testCapabilityChecks() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingTransport)

    // Verify capability inference
    let toolConns = await host.connections(supporting: .tools)
    #expect(!toolConns.isEmpty)
    #expect(toolConns.contains(connection))

    let resourceConns = await host.connections(supporting: .resources)
    #expect(!resourceConns.isEmpty)
    #expect(resourceConns.contains(connection))

    // Connection API should respect capabilities
    await connection.refresh()
    #expect(connection.capabilities.supports(.tools))
    #expect(!connection.tools.isEmpty)

    // Test capability changes
    let noCapConn = ConnectionState(
      id: "test2",
      client: connection.client,
      serverInfo: connection.serverInfo,
      capabilities: .init()
    )

    await noCapConn.refreshTools()
    #expect(noCapConn.tools.isEmpty)
  }

  @Test("Host monitors connection health")
  func testHealthMonitoring() async throws {
    let host = MCPHost()
    let connection = try await host.connect("test", transport: everythingTransport)

    // Initially active
    var inactive = await host.inactiveConnections(timeout: 60)
    #expect(inactive.isEmpty)

    // Force inactivity
    let oldActivity = connection.lastActivity
    try await Task.sleep(for: .seconds(2))

    inactive = await host.inactiveConnections(timeout: 1)
    #expect(!inactive.isEmpty)
    #expect(inactive.first?.lastActivity == oldActivity)

    // Activity updates on operations
    await connection.refreshTools()
    inactive = await host.inactiveConnections(timeout: 1)
    #expect(connection.lastActivity > oldActivity)
    #expect(inactive.isEmpty)
  }
}
