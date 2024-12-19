import Foundation

/// Transport implementation using Server-Sent Events (SSE)
public actor SSETransport: MCPTransport {
    public private(set) var state: TransportState = .disconnected
    public let configuration: TransportConfiguration

    private let endpoint: URL
    private let sessionId: String
    private var eventSource: URLSessionStreamTask?
    private var messagesContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(
        endpoint: URL,
        configuration: TransportConfiguration = .default,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.configuration = configuration
        self.session = session
        self.sessionId = UUID().uuidString
    }

    public func messages() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            self.messagesContinuation = continuation

            // Auto-start if needed
            Task {
                if self.state == .disconnected {
                    do {
                        try await self.start()
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }

                // Setup event monitoring
                await self.startEventMonitoring()
            }

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.stop()
                }
            }
        }
    }

    public func start() async throws {
        guard state == .disconnected else {
            throw TransportError.invalidState("Transport already started")
        }

        // TODO: implement
    }

    public func stop() async {
        eventSource?.cancel()
        eventSource = nil
        messagesContinuation?.finish()
        state = .disconnected
    }

    public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
        guard state == .connected else {
            throw TransportError.invalidState("Transport not connected")
        }

        // Check message size
        if data.count > configuration.maxMessageSize {
            throw TransportError.messageTooLarge(data.count)
        }

        // Prepare request
        var url = endpoint
        url.append(queryItems: [URLQueryItem(name: "sessionId", value: sessionId)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        // Set timeout if provided
        if let timeout = timeout {
            request.timeoutInterval = timeout
        } else {
            request.timeoutInterval = configuration.sendTimeout
        }

        // Send request with timeout
        let (_, response) = try await session.data(
            for: request,
            delegate: nil
        )

        // Verify response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.invalidState("Non-HTTP response received")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TransportError.invalidState(httpResponse.statusCode.description)
        }
    }

    /// Monitor SSE events from the server
    private func startEventMonitoring() async {
        // TODO: implement

        messagesContinuation?.finish()
    }

    private func setEventSource(_ task: URLSessionStreamTask) {
        self.eventSource = task
    }
}
