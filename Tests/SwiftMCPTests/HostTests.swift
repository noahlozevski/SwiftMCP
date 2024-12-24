import Foundation
import Testing

@testable import SwiftMCP

@Suite("MCP Hosts")
struct MCPHostTests {
  let configuration = MCPHostConfiguration(
    clientConfig: MCPClient.Configuration(
      clientInfo: Implementation(name: "Test Client", version: "1"),
      capabilities: ClientCapabilities())
  )

  @Test
  func testHostConnection() async throws {
    let host = MCPHost(configuration: configuration)

    let transport = StdioTransport(
      command: "npx", arguments: ["-y", "@modelcontextprotocol/server-memory"])
    try await host.connect("memory", transport: transport)

    var tools = await host.availableTools()

    #expect(tools.count > 0)

    await host.disconnect("memory")

    tools = await host.availableTools()

    #expect(tools.count == 0)

    let client = await host.client(id: "memory")
    #expect(client == nil)
  }

}
