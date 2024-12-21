import Foundation

/// A client implementation of the Model Context Protocol
public actor MCPClient: MCPEndpoint {
  // MARK: - Properties

  public private(set) var state: MCPEndpointState = .disconnected
  public let notifications: AsyncStream<MCPNotification>

  private var transport: (any MCPTransport)?
  private var requestHandlers: [RequestID: ResponseHandler] = [:]
  private var messageProcessingTask: Task<Void, Error>?
  private let notificationsContinuation: AsyncStream<MCPNotification>.Continuation
  private let clientInfo: Implementation
  private let clientCapabilities: ClientCapabilities

  // MARK: - Initialization

  public init(
    clientInfo: Implementation,
    capabilities: ClientCapabilities = .init()
  ) {
    // Setup notifications stream
    var continuation: AsyncStream<MCPNotification>.Continuation!
    self.notifications = AsyncStream { continuation = $0 }
    self.notificationsContinuation = continuation
    self.clientCapabilities = capabilities
    self.clientInfo = clientInfo
  }

  // MARK: - Connection Management

  public func start(_ transport: any MCPTransport) async throws {
    if case .running = state {
      await stop()
    }

    self.transport = transport
    state = .connecting

    // Start message processing
    messageProcessingTask = Task {
      guard let transport = self.transport else {
        throw MCPError.internalError("Transport not available")
      }
      try await transport.start()
      do {
        let messageStream = await transport.messages()
        for try await data in messageStream {
          if Task.isCancelled { break }
          try await processIncomingMessage(data)
        }
      } catch {
        await handleError(error)
      }
    }

    // Perform initialization
    state = .initializing
    do {
      let capabilities = try await performInitialization()
      state = .running(capabilities)
    } catch {
      state = .failed(MCPError.internalError("Failed to initialize server connection"))
    }
  }

  public func stop() async {
    messageProcessingTask?.cancel()
    messageProcessingTask = nil
    await transport?.stop()

    // Cancel all pending requests
    let error = MCPError.internalError("Client stopped")
    for handler in requestHandlers.values {
      handler.cancel(error)
    }
    requestHandlers.removeAll()

    state = .disconnected
  }

  // MARK: - Request Handling

  public func send<R: MCPRequest>(_ request: R) async throws -> R.Response {
    guard case .running(let capabilities) = state else {
      throw MCPError.internalError("Client must be running to send requests")
    }

    // Validate capabilities for this request type
    try validateCapabilities(capabilities, for: request)

    return try await sendRequest(request)
  }

  // MARK: - Private Methods

  /// Send a request without state validation - used only for initialization
  private func sendRequest<R: MCPRequest>(_ request: R) async throws -> R.Response {
    guard let transport else {
      throw MCPError.internalError("Transport not available")
    }
    // Create message with unique ID
    let requestId = RequestID.string(UUID().uuidString)
    let message = JSONRPCMessage<R>.request(id: requestId, request: request)

    // Setup response handling
    return try await withCheckedThrowingContinuation { continuation in
      let handler = TypedResponseHandler<R>(continuation: continuation)
      requestHandlers[requestId] = handler

      Task {
        do {
          let data = try JSONEncoder().encode(message)
          try await transport.send(data)
        } catch {
          // Clean up handler on send failure
          requestHandlers.removeValue(forKey: requestId)
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func processIncomingMessage(_ data: Data) async throws {
    // First try as notification
    if let message = try? JSONDecoder().decode(
      JSONRPCMessage<EmptyRequest>.self,
      from: data
    ) {
      if case .notification(let notification) = message {
        notificationsContinuation.yield(notification)
        return
      }
    }

    // Try each response handler
    for (id, handler) in requestHandlers where try handler.handle(data) {
      requestHandlers.removeValue(forKey: id)
      return
    }

    // Ignore unmatched messages - they might be for cancelled requests
  }

  private func performInitialization() async throws -> ServerCapabilities {
    guard let transport else {
      throw MCPError.internalError("Transport not available")
    }

    let request = InitializeRequest(
      params: .init(
        capabilities: clientCapabilities,
        clientInfo: clientInfo,
        protocolVersion: MCPVersion.currentVersion
      ))

    let response = try await sendRequest(request)  // Use sendRequest directly, bypassing state validation

    // Validate protocol version
    guard MCPVersion.supportedVersions.contains(response.protocolVersion) else {
      throw MCPError.invalidRequest(
        "Server version \(response.protocolVersion) not supported")
    }

    // Send initialized notification
    let notification = InitializedNotification()
    let message = JSONRPCMessage<InitializeRequest>.notification(notification)
    let data = try JSONEncoder().encode(message)
    try await transport.send(data)

    return response.capabilities
  }

  private func validateCapabilities(
    _ capabilities: ServerCapabilities, for request: any MCPRequest
  ) throws {
    switch request {
    case is ListPromptsRequest:
      guard capabilities.prompts != nil else {
        throw MCPError.invalidRequest("Server does not support prompts")
      }
    case is ListResourcesRequest, is ReadResourceRequest:
      guard capabilities.resources != nil else {
        throw MCPError.invalidRequest("Server does not support resources")
      }
    case is ListToolsRequest, is CallToolRequest:
      guard capabilities.tools != nil else {
        throw MCPError.invalidRequest("Server does not support tools")
      }
    case is SetLevelRequest:
      guard capabilities.logging != nil else {
        throw MCPError.invalidRequest("Server does not support logging")
      }
    case is InitializeRequest:
      // Always allowed
      break
    default:
      // For unknown request types, allow them through
      // This enables future protocol extensions
      break
    }
  }

  private func handleError(_ error: Error) async {
    state = .failed(error)

    // Cancel all pending requests
    for handler in requestHandlers.values {
      handler.cancel(error)
    }
    requestHandlers.removeAll()
  }
}

// MARK: Client API
extension MCPClient {
  public func listPrompts() async throws -> ListPromptsResult {
    try await send(ListPromptsRequest())
  }

  public func listTools() async throws -> ListToolsResult {
    try await send(ListToolsRequest())
  }

  // TODO: Don't expose anycodable
  public func callTool(
    _ toolName: String,
    with arguments: [String: AnyCodable]? = nil
  ) async throws -> CallToolResult {
    try await send(CallToolRequest(name: toolName, arguments: arguments))
  }

  public func setLoggingLevel(_ level: LoggingLevel) async throws {
    _ = try await send(SetLevelRequest(level: level))
  }

  public func listResources(_ cursor: String? = nil) async throws -> ListResourcesResult {
    try await send(ListResourcesRequest(cursor: cursor))
  }

  public func listResourceTemplates(
    _ cursor: String? = nil
  ) async throws -> ListResourceTemplatesResult {
    try await send(ListResourceTemplatesRequest(cursor: cursor))
  }

  public func readResource(_ uri: String) async throws -> ReadResourceResult {
    try await send(ReadResourceRequest(uri: uri))
  }
}
