import Foundation

public enum MCPClientEvent {
  case connectionChanged(MCPEndpointState<InitializeResult>)
  // TODO: Implement below events
  case message(any MCPMessage)
  case error(Error)
}

/// A client implementation of the Model Context Protocol
public actor MCPClient: MCPEndpointProtocol {
  // MARK: - Properties

  public private(set) var state: MCPEndpointState<SessionInfo> = .disconnected {
    didSet {
      eventsContinuation.yield(.connectionChanged(state))
    }
  }

  public let notifications: AsyncStream<any MCPNotification>
  private let notificationsContinuation: AsyncStream<any MCPNotification>.Continuation
  public let events: AsyncStream<MCPClientEvent>
  private let eventsContinuation: AsyncStream<MCPClientEvent>.Continuation

  private var pendingRequests: [RequestID: any PendingRequestProtocol] = [:]
  private var requestHandlers: [String: ServerRequestHandler] = [:]

  private var messageTask: Task<Void, Error>?

  private var transport: (any MCPTransport)?
  private let clientInfo: Implementation
  private let clientCapabilities: ClientCapabilities

  private var currentRoots: [Root] = []

  private let progressManager = ProgressManager()

  public var isConnected: Bool {
    guard case .running = state else {
      return false
    }
    return true
  }

  // MARK: - Initialization
  init(configuration: Configuration) {
    self.init(clientInfo: configuration.clientInfo, capabilities: configuration.capabilities)
  }

  public init(
    clientInfo: Implementation,
    capabilities: ClientCapabilities = .init()
  ) {
    // Setup notifications stream
    var continuation: AsyncStream<any MCPNotification>.Continuation!
    self.notifications = AsyncStream { continuation = $0 }
    self.notificationsContinuation = continuation
    self.clientCapabilities = capabilities
    self.clientInfo = clientInfo
    var eventsContinuation: AsyncStream<MCPClientEvent>.Continuation!
    self.events = AsyncStream { eventsContinuation = $0 }
    self.eventsContinuation = eventsContinuation
  }

  // MARK: - Connection Management

  public func start(_ transport: any MCPTransport) async throws {
    if case .running = state {
      await stop()
    }

    self.transport = transport
    state = .connecting

    // Start message processing
    messageTask = Task {
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
    // Cancel message processing
    messageTask?.cancel()
    messageTask = nil

    // Cancel pending requests
    let error = MCPError.internalError("Client stopped")
    for request in pendingRequests.values {
      request.cancel(with: error)
    }
    pendingRequests.removeAll()

    await transport?.stop()
    transport = nil
    state = .disconnected
  }

  public func reconnect() async throws {
    guard case .disconnected = state else {
      throw MCPError.internalError("Can only reconnect when disconnected")
    }

    guard let transport = self.transport else {
      throw MCPError.internalError("Transport not available")
    }

    state = .connecting
    await transport.stop()
    try await transport.start()
    do {
      let capabilities = try await performInitialization()
      state = .running(capabilities)
    } catch {
      state = .failed(MCPError.internalError("Failed to initialize server connection"))
    }
  }

  // MARK: - Request Handling

  public func send<R: MCPRequest>(_ request: R) async throws -> R.Response {
    try await send(request, progressHandler: nil)
  }

  public func send<R: MCPRequest>(
    _ request: R,
    progressHandler: ProgressHandler.UpdateHandler? = nil
  ) async throws -> R.Response {
    guard case .running(let session) = state else {
      throw MCPError.internalError("Client must be running to send requests")
    }

    // Validate capabilities for this request type
    try validateCapabilities(session.capabilities, for: request)

    return try await sendRequest(request, progressHandler: progressHandler)
  }

  // MARK: - Notification Handling

  public func emit<N: MCPNotification>(_ notification: N) async throws {
    guard case .running = state else {
      throw MCPError.internalError("Client must be running to send notifications")
    }

    let message = JSONRPCMessage.notification(notification)
    let data = try JSONEncoder().encode(message)
    try await transport?.send(data)
  }

  // MARK: - Request Handlers
  public func registerHandler<R: MCPRequest>(
    for request: R.Type,
    handler: @escaping (R) async throws -> R.Response
  ) {
    let handler: ServerRequestHandler = { request in
      guard let typedRequest = request as? R else {
        throw MCPError.invalidRequest("Unexpected request type")
      }
      return try await handler(typedRequest)
    }

    requestHandlers[request.method] = handler
  }

  public func updateRoots(_ roots: [Root]?) async throws {
    guard let roots = roots else {
      currentRoots = []
      return
    }

    try await notifyRootsChanged(roots)
  }

  // MARK: - Private Methods

  /// Send a request without state validation - used only for initialization
  private func sendRequest<R: MCPRequest>(
    _ request: R,
    progressHandler: ProgressHandler.UpdateHandler? = nil
  ) async throws -> R.Response {
    guard let transport = transport else {
      throw MCPError.connectionClosed()
    }

    let requestId = RequestID.string(UUID().uuidString)
    var request = request
    if let progressHandler {
      let meta = RequestMeta(progressToken: requestId)
      request.params._meta = meta
      let handler = ProgressHandler(token: requestId, handler: progressHandler)
      await progressManager.register(handler, for: requestId)
    }

    let message = JSONRPCMessage.request(id: requestId, request: request)

    return try await withCheckedThrowingContinuation { continuation in
      // Create timeout
      let timeoutTask = Task {
        try? await Task.sleep(for: .seconds(transport.configuration.sendTimeout))
        if pendingRequests[requestId] != nil {
          pendingRequests.removeValue(forKey: requestId)
          await continuation.resume(
            throwing: MCPError.timeout(
              R.method, duration: transport.configuration.sendTimeout
            )
          )
        }
      }

      // Track request
      pendingRequests[requestId] = PendingRequest<R.Response>(
        continuation: continuation,
        timeoutTask: timeoutTask
      )

      // Send request
      Task {
        do {
          let data = try JSONEncoder().encode(message)
          try await transport.send(data)
        } catch {
          if let pending = pendingRequests.removeValue(forKey: requestId) {
            pending.cancel(with: error)
          }
        }
      }
    }
  }

  private func processIncomingMessage(_ data: Data) async throws {
    guard
      let message = try? JSONDecoder().decode(
        JSONRPCMessage.self,
        from: data
      )
    else {
      return
    }
    switch message {
    case .notification(let notification):
      switch notification {
      case let cancelled as CancelledNotification:
        try await handleCancelledRequest(cancelled)
        return
      case let progress as ProgressNotification:
        await progressManager.handle(progress)
        return
      default:
        notificationsContinuation.yield(notification)
        return
      }
    case .response(let id, let result):
      await handleResponse(id, result)
      return
    case .error(let id, let error):
      if let handler = pendingRequests[id] {
        handler.cancel(with: error)

        pendingRequests.removeValue(forKey: id)
      }
      await progressManager.unregister(for: id)
      return
    case .request(let id, let request):
      try await handleRequest(id, request)
    }
  }

  private func handleResponse(_ id: RequestID, _ resultCodable: AnyCodable) async {
    if let handler = pendingRequests[id] {
      do {
        let data = try JSONEncoder().encode(resultCodable)
        let response = try JSONDecoder().decode(handler.responseType, from: data)
        try pendingRequests[id]?.complete(with: response)
      } catch {
        pendingRequests[id]?.cancel(with: error)
      }
      pendingRequests.removeValue(forKey: id)
    }
    await progressManager.unregister(for: id)
  }

  private func handleRequest(_ id: RequestID, _ request: any MCPRequest) async throws {
    let method = type(of: request).method
    guard let handler = requestHandlers[method] else {
      let error = MCPError.methodNotFound(method)
      let message = JSONRPCMessage.error(id: id, error: error)
      let data = try JSONEncoder().encode(message)
      try await transport?.send(data)
      return
    }

    do {
      let response = try await handler(request)
      let message = JSONRPCMessage.response(id, response: response)
      let data = try JSONEncoder().encode(message)
      try await transport?.send(data)
    } catch {
      let mcpError = error as? MCPError ?? MCPError.internalError(error.localizedDescription)
      let message = JSONRPCMessage.error(id: id, error: mcpError)
      let data = try JSONEncoder().encode(message)
      try await transport?.send(data)
    }
  }

  private func registerDefaultRequestHandlers() {
    registerHandler(for: ListRootsRequest.self) { [unowned self] _ in
      try await handleListRoots(ListRootsRequest())
    }
  }

  private func handleCancelledRequest(_ notification: CancelledNotification) async throws {
    guard let handler = pendingRequests[notification.params.requestId] else {
      return
    }

    handler.cancel(with: MCPError.internalError("Request was cancelled"))
    pendingRequests.removeValue(forKey: notification.params.requestId)
  }

  private func performInitialization() async throws -> SessionInfo {
    guard let transport else {
      throw MCPError.internalError("Transport not available")
    }

    let request = InitializeRequest(
      params: .init(
        capabilities: clientCapabilities,
        clientInfo: clientInfo,
        protocolVersion: MCPVersion.currentVersion
      ))

    // Initialize request needs to be sent without validation
    let response = try await sendRequest(request)

    // Validate protocol version
    guard MCPVersion.isSupported(response.protocolVersion) else {
      throw MCPError.invalidRequest(
        "Server version \(response.protocolVersion) not supported")
    }

    // Send initialized notification
    let notification = InitializedNotification()
    let message = JSONRPCMessage.notification(notification)
    let data = try JSONEncoder().encode(message)
    try await transport.send(data)

    return response
  }

  private func validateCapabilities(
    _ capabilities: ServerCapabilities,
    for request: any MCPRequest
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
    for handler in pendingRequests.values {
      handler.cancel(with: error)
    }
    pendingRequests.removeAll()
  }

  func notifyRootsChanged(_ roots: [Root]) async throws {
    // Only notify if roots actually changed
    guard roots != currentRoots else { return }
    currentRoots = roots

    // Automatically handle roots capability and notification
    try await emit(RootsListChangedNotification())
  }

  // Simplified handler for list roots request
  private func handleListRoots(_ request: ListRootsRequest) async throws -> ListRootsResult {
    return ListRootsResult(roots: currentRoots)
  }
}

// MARK: Client API
extension MCPClient {
  public func listPrompts(
    cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ListPromptsResult {
    try await send(ListPromptsRequest(cursor: cursor), progressHandler: progress)
  }

  public func getPrompt(
    _ name: String,
    arguments: [String: String]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> GetPromptResult {
    try await send(
      GetPromptRequest(name: name, arguments: arguments ?? [:]), progressHandler: progress
    )
  }

  public func listTools(
    cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ListToolsResult {
    try await send(ListToolsRequest(cursor: cursor), progressHandler: progress)
  }

  public func callTool(
    _ toolName: String,
    with arguments: [String: Any]? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> CallToolResult {
    try await send(
      CallToolRequest(
        name: toolName,
        arguments: arguments ?? [:]
      ),
      progressHandler: progress
    )
  }

  public func setLoggingLevel(
    _ level: LoggingLevel,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws {
    _ = try await send(SetLevelRequest(level: level), progressHandler: progress)
  }

  public func listResources(
    _ cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ListResourcesResult {
    try await send(ListResourcesRequest(cursor: cursor), progressHandler: progress)
  }

  public func subscribe(
    to uri: String,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws {
    _ = try await send(SubscribeRequest(uri: uri))
  }

  public func unsubscribe(
    from uri: String,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws {
    _ = try await send(UnsubscribeRequest(uri: uri), progressHandler: progress)
  }

  public func listResourceTemplates(
    _ cursor: String? = nil,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ListResourceTemplatesResult {
    try await send(ListResourceTemplatesRequest(cursor: cursor), progressHandler: progress)
  }

  public func readResource(
    _ uri: String,
    progress: ProgressHandler.UpdateHandler? = nil
  ) async throws -> ReadResourceResult {
    try await send(ReadResourceRequest(uri: uri), progressHandler: progress)
  }

  public func ping() async throws {
    _ = try await send(PingRequest())
  }
}

extension MCPClient {
  public typealias ServerRequestHandler = (any MCPRequest) async throws -> any MCPResponse

  public typealias SessionInfo = InitializeResult

  public struct Configuration {
    public let clientInfo: Implementation
    public let capabilities: ClientCapabilities

    public init(clientInfo: Implementation, capabilities: ClientCapabilities) {
      self.clientInfo = clientInfo
      self.capabilities = capabilities
    }

    public static let `default` = Configuration(
      clientInfo: .defaultClient,
      capabilities: .init()
    )
  }

  private protocol PendingRequestProtocol {
    func cancel(with error: Error)
    func complete(with response: any MCPResponse) throws

    var responseType: any MCPResponse.Type { get }
  }

  private struct PendingRequest<Response: MCPResponse>: PendingRequestProtocol {
    let continuation: CheckedContinuation<Response, any Error>
    let timeoutTask: Task<Void, Never>?

    var responseType: any MCPResponse.Type { Response.self }

    func cancel(with error: Error) {
      timeoutTask?.cancel()
      continuation.resume(throwing: error)
    }

    func complete(with response: any MCPResponse) throws {
      guard let typedResponse = response as? Response else {
        throw MCPError.internalError("Unexpected response type")
      }
      timeoutTask?.cancel()
      continuation.resume(returning: typedResponse)
    }
  }
}
