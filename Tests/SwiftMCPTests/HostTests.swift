import Foundation
import Testing

@testable import SwiftMCP

/// # Everything MCP Server
///
/// This MCP server attempts to exercise all the features of the MCP protocol. It is not intended to be a useful server, but rather a test server for builders of MCP clients. It implements prompts, tools, resources, sampling, and more to showcase MCP capabilities.
///
/// ## Components
///
/// ### Tools
///
/// 1. `echo`
///    - Simple tool to echo back input messages
///    - Input:
///      - `message` (string): Message to echo back
///    - Returns: Text content with echoed message
///
/// 2. `add`
///    - Adds two numbers together
///    - Inputs:
///      - `a` (number): First number
///      - `b` (number): Second number
///    - Returns: Text result of the addition
///
/// 3. `longRunningOperation`
///    - Demonstrates progress notifications for long operations
///    - Inputs:
///      - `duration` (number, default: 10): Duration in seconds
///      - `steps` (number, default: 5): Number of progress steps
///    - Returns: Completion message with duration and steps
///    - Sends progress notifications during execution
///
/// 4. `sampleLLM`
///    - Demonstrates LLM sampling capability using MCP sampling feature
///    - Inputs:
///      - `prompt` (string): The prompt to send to the LLM
///      - `maxTokens` (number, default: 100): Maximum tokens to generate
///    - Returns: Generated LLM response
///
/// 5. `getTinyImage`
///    - Returns a small test image
///    - No inputs required
///    - Returns: Base64 encoded PNG image data
///
/// 6. `printEnv`
///    - Prints all environment variables
///    - Useful for debugging MCP server configuration
///    - No inputs required
///    - Returns: JSON string of all environment variables
///
/// ### Resources
///
/// The server provides 100 test resources in two formats:
/// - Even numbered resources:
///   - Plaintext format
///   - URI pattern: `test://static/resource/{even_number}`
///   - Content: Simple text description
///
/// - Odd numbered resources:
///   - Binary blob format
///   - URI pattern: `test://static/resource/{odd_number}`
///   - Content: Base64 encoded binary data
///
/// Resource features:
/// - Supports pagination (10 items per page)
/// - Allows subscribing to resource updates
/// - Demonstrates resource templates
/// - Auto-updates subscribed resources every 5 seconds
///
/// ### Prompts
///
/// 1. `simple_prompt`
///    - Basic prompt without arguments
///    - Returns: Single message exchange
///
/// 2. `complex_prompt`
///    - Advanced prompt demonstrating argument handling
///    - Required arguments:
///      - `temperature` (number): Temperature setting
///    - Optional arguments:
///      - `style` (string): Output style preference
///    - Returns: Multi-turn conversation with images
///
/// ## Usage with Claude Desktop
///
/// Add to your `claude_desktop_config.json`:
///
/// ```json
/// {
///   "mcpServers": {
///     "everything": {
///       "command": "npx",
///       "args": [
///         "-y",
///         "@modelcontextprotocol/server-everything"
///       ]
///     }
///   }
/// }
/// ```
@Suite("MCP Hosts")
struct MCPHostTests {
  var configuration = MCPConfiguration(
    roots: .list([])
  )

  let everythingTransport = StdioTransport(
    command: "npx", arguments: ["-y", "@modelcontextprotocol/server-everything"]
  )

  @Test
  func testHostConnection() async throws {
    let host = MCPHost(config: configuration)

    let transport = StdioTransport(
      command: "npx", arguments: ["-y", "@modelcontextprotocol/server-memory"])
    let connection = try await host.connect("memory", transport: transport)

    await connection.fetch(.tools)
    let toolState = await connection.tools

    #expect(toolState.tools.count > 0)

    await host.disconnect(connection.id)

    let isConnected = await connection.isConnected

    #expect(!isConnected)
  }

  @Test
  func testEverythingServerTools() async throws {
    let host = MCPHost(config: configuration)

    let connection = try await host.connect("everything", transport: everythingTransport)

    await connection.fetch(.tools)

    let toolsApi = await connection.tools
    var tools = toolsApi.tools

    #expect(tools.count > 0)

    let echoResponse = try await toolsApi.call("echo", arguments: ["message": "Hello, World!"])
    let echoContent = try #require(echoResponse.content.first)
    guard case let .text(echoMessage) = echoContent else {
      Issue.record("Expected string content for echo tool")
      return
    }

    #expect(echoMessage.text == "Echo: Hello, World!")

    let addResponse = try await toolsApi.call("add", arguments: ["a": 1, "b": 2])
    let addContent = try #require(addResponse.content.first)
    guard case let .text(addResult) = addContent else {
      Issue.record("Expected string content for add tool")
      return
    }

    #expect(addResult.text.contains("3"))

    // Image
    let imageResponse = try await toolsApi.call("getTinyImage", arguments: [:])

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
  func testLongRunningOperation() async throws {
    let host = MCPHost(config: configuration)

    let connection = try await host.connect("everything", transport: everythingTransport)

    await connection.fetch(.tools)
    let toolsApi = await connection.tools
    let tools = toolsApi.tools

    #expect(tools.count > 0)

    var progressCalled = false

    // Progress notifications (TODO)
    let longRunningResponse = try await toolsApi.call(
      "longRunningOperation", arguments: [
        "duration": 5,
        "step": 10
      ]
    ) {
      (a, b) in
      print(a, b)
      progressCalled = true
    }

    try await Task.sleep(for: .seconds(5))
    print(progressCalled)
    #expect(progressCalled)

    // Image
    let imageResponse = try await toolsApi.call("getTinyImage", arguments: [:])

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
  func testEverythingServerSampling() async throws {
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

    let tools = await connection.tools

    let sampleResponse = try await tools.call(
      "sampleLLM", arguments: ["prompt": "Hello, World!"])
    print(sampleResponse)
    #expect(sampleResponse.content.count > 0)
  }

  @Test
  func testEverythingServerResources() async throws {
    let host = MCPHost()

    let connection = try await host.connect("test", transport: everythingTransport)

    await connection.fetch(.resources)

    let resourceState = await connection.resources

    print(resourceState.resources)
    #expect(resourceState.resources.count > 0)

    let textResource = try await resourceState.read("test://static/resource/1")
    #expect(textResource.contents.count > 0)

    let binaryResource = try await resourceState.read("test://static/resource/2")
    #expect(binaryResource.contents.count > 0)
  }

  @Test
  func testPrompts() async throws {
    let host = MCPHost()

    let connection = try await host.connect("test", transport: everythingTransport)

    await connection.fetch(.prompts)

    let promptState = await connection.prompts

    let simplePrompt = try await promptState.get("simple_prompt")
    #expect(simplePrompt.messages.count > 0)

    let complexPrompt = try await promptState.get(
      "complex_prompt",
      arguments: ["temperature": "72"]
    )
    #expect(complexPrompt.messages.count > 0)

    print(complexPrompt)
    print(simplePrompt)
  }
}
