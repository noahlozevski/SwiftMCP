import Foundation
import Testing

@testable import SwiftMCP

/// Mock transport for testing
actor MockTransport: MCPTransport {
  var state: TransportState = .disconnected
  let configuration: TransportConfiguration

  private var messageStream: AsyncStream<Data>
  private let messageContinuation: AsyncStream<Data>.Continuation
  private var queuedResponses: [(Data) async throws -> Data] = []
  private var sentMessages: [Data] = []

  init(configuration: TransportConfiguration = .default) {
    self.configuration = configuration

    var continuation: AsyncStream<Data>.Continuation!
    self.messageStream = AsyncStream { continuation = $0 }
    self.messageContinuation = continuation
  }

  func messages() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      Task {
        for try await message in messageStream {
          continuation.yield(message)
        }
        continuation.finish()
      }
    }
  }

  func start() async throws {
    state = .connected
  }

  func stop() async {
    state = .disconnected
    messageContinuation.finish()
  }

  func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    sentMessages.append(data)

    // Only process requests, not notifications
    if let message = try? JSONDecoder().decode(
      JSONRPCMessage<InitializeRequest>.self,
      from: data
    ) {
      switch message {
      case .request:
        // Process the request with next handler
        if let handler = queuedResponses.first {
          queuedResponses.removeFirst()
          let response = try await handler(data)
          messageContinuation.yield(response)
        }
      case .notification:
        // Just record the notification, don't consume a response handler
        break
      default:
        break
      }
    }
  }

  func queueResponse(_ handler: @escaping (Data) async throws -> Data) {
    queuedResponses.append(handler)
  }

  func queueError(_ error: Error) {
    queuedResponses.append { _ in throw error }
  }

  func queueInitSuccess() {
    queueResponse { _ in
      let response = JSONRPCMessage<InitializeRequest>.response(
        id: .string("1"),
        response: InitializeResult(
          capabilities: ServerCapabilities(
            prompts: .init(listChanged: true),
            resources: .init(listChanged: true),
            tools: .init(listChanged: true)
          ),
          protocolVersion: MCPVersion.currentVersion,
          serverInfo: .init(name: "Test", version: "1.0")
        )
      )
      return try JSONEncoder().encode(response)
    }
  }

  func sentMessageCount() -> Int {
    sentMessages.count
  }

  func lastSentMessage<T: Decodable>(_ type: T.Type) throws -> T {
    guard let data = sentMessages.last else {
      throw MCPError.internalError("No messages sent")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  func emitNotification(_ notification: MCPNotification) throws {
    let message = JSONRPCMessage<InitializeRequest>.notification(notification)
    let data = try JSONEncoder().encode(message)
    messageContinuation.yield(data)
  }
}

@Suite("MCPClient Tests")
struct MCPClientTests {
  private var client = MCPClient(clientInfo: .init(name: "test", version: "1.0"))

  @Test("Successfully initializes and connects")
  func testInitialization() async throws {
    let transport = MockTransport()
    await transport.queueInitSuccess()

    try await client.start(transport)

    // Verify state transitions
    let finalState = await client.state
    guard case .running = finalState else {
      throw MCPError.internalError("Expected running state")
    }

    let count = await transport.sentMessageCount()
    try #require(count == 2)  // Init request + notification

    let initMessage: JSONRPCMessage<InitializeRequest> =
      try await transport.lastSentMessage(JSONRPCMessage<InitializeRequest>.self)
    guard case .notification = initMessage else {
      throw MCPError.internalError("Expected notification")
    }
  }

  @Test("Handles initialization failure")
  func testInitializationFailure() async throws {
    let transport = MockTransport()
    await transport.queueError(MCPError.internalError("Init failed"))

    do {
      try await client.start(transport)
      throw MCPError.internalError("Expected failure")
    } catch {
      let finalState = await client.state
      guard case .failed = finalState else {
        throw MCPError.internalError("Expected failed state")
      }
    }
  }

  @Test(
    "Successfully sends requests and receives responses"
  )
  func testRequestResponse() async throws {
    let transport = StdioTransport(
      command: "npx", arguments: ["-y", "@modelcontextprotocol/server-memory"])

    try #require(await client.start(transport))
    let result = try #require(await client.listTools())
    #expect(result.tools.count > 0)

    await client.stop()
  }

  @Test("Handles notifications")
  func testNotifications() async throws {
    let transport = MockTransport()
    await transport.queueInitSuccess()

    try await client.start(transport)

    var receivedNotifications: [MCPNotification] = []
    let notificationTask = Task {
      for await notification in await client.notifications {
        receivedNotifications.append(notification)
        if receivedNotifications.count == 2 {
          break
        }
      }
    }

    try await transport.emitNotification(
      PromptListChangedNotification()
    )
    try await transport.emitNotification(
      ResourceListChangedNotification()
    )

    _ = await notificationTask.value

    #expect(receivedNotifications.count == 2)
    #expect(receivedNotifications[0] is PromptListChangedNotification)
    #expect(receivedNotifications[1] is ResourceListChangedNotification)
  }

  @Test("Validates capabilities")
  func testCapabilityValidation() async throws {
    let transport = MockTransport()
    // Queue initialization with no prompts capability
    await transport.queueResponse { _ in
      let response = JSONRPCMessage<InitializeRequest>.response(
        id: .string("1"),
        response: InitializeResult(
          capabilities: ServerCapabilities(),  // No capabilities
          protocolVersion: MCPVersion.currentVersion,
          serverInfo: Implementation(name: "Test", version: "1.0")
        )
      )
      return try JSONEncoder().encode(response)
    }

    try await client.start(transport)

    do {
      _ = try await client.send(ListPromptsRequest())
      throw MCPError.internalError("Expected capability validation failure")
    } catch {
      #expect(error is MCPError)
      #expect("\(error)".contains("does not support prompts"))
    }
  }

  @Test("Handles clean shutdown")
  func testShutdown() async throws {
    let transport = MockTransport()
    await transport.queueInitSuccess()

    try await client.start(transport)
    await client.stop()

    let finalState = await client.state
    guard case .disconnected = finalState else {
      throw MCPError.internalError("Expected disconnected state")
    }

    let transportState = await transport.state
    guard case .disconnected = transportState else {
      throw MCPError.internalError("Expected disconnected transport")
    }
  }
}
