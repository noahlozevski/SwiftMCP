import os // for logger
import Foundation

public actor SSEClientTransport: MCPTransport {
    public let configuration: TransportConfiguration
    /// The current state of the transport
    public private(set) var state: TransportState = .disconnected
    /// The endpoint we receive via the `endpoint` SSE event. Once known, we POST to it for sending messages.
    public private(set) var postEndpoint: URL?

    /// The base URL for the SSE connection (GET) request.
    private let url: URL

    /// Used for parsing SSE events
    private var currentEvent: String?

    /// Our internal `EventSource` task
    private var task: Task<Void, Never>?

    /// The continuation for the AsyncThrowingStream
    private var messagesContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    /// A unique session identifier
    private let sessionId: String

    /// Extra request configuration (like headers) if needed
    private let urlSession: URLSession

    private let logger: Logger

    public init(
        url: URL,
        configuration: TransportConfiguration = .default,
        urlSession: URLSession = .shared
    ) {
        self.url = url
        self.configuration = configuration
        self.urlSession = urlSession
        self.sessionId = UUID().uuidString
        self.logger = Logger(subsystem: "SwiftMCP", category: "SSEClientTransport")
        self.currentEvent = nil
    }

    /// Create a stream of messages from the SSE connection
    /// This needs to be called before the downchannel is created
    public func messages() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            self.messagesContinuation = continuation
            Task {
                do {
                    if self.state != .connected {
                        // auto start the connection if not already connected
                        try await self.start()
                    }

                    // start the downchannel
                    self.readSSEEvents(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.stop()
                }
            }
        }
    }

    /// Start the SSE connection
    public func start() async throws {
        guard state != .connected else {
            throw TransportError.invalidState("Transport is already started")
        }

        // the downchannel is only created when the `messages` iterator is active
        // the state will move to "connected" once that completes
        self.setState(.connecting)
    }

    /// Stop the SSE connection
    public func stop() {
        if state == .disconnected {
            return
        }
        self.setState(.disconnected)

        // Cancel any ongoing Task
        task?.cancel()
        task = nil

        // Finish the messages stream
        messagesContinuation?.finish()
        messagesContinuation = nil
    }

    /// Send data to the server via POST. We must have received the server-provided `postEndpoint` first.
    public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
        guard state == .connected else {
            throw TransportError.invalidState("Transport not connected")
        }

        guard let endpoint = postEndpoint else {
            throw TransportError.invalidState("Server endpoint not known yet")
        }

        if data.count > configuration.maxMessageSize {
            throw TransportError.messageTooLarge(data.count)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        // Timeout logic
        let actualTimeout = timeout ?? configuration.sendTimeout
        request.timeoutInterval = actualTimeout

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw TransportError.invalidState("POST failed to \(endpoint)")
        }
        logger.info("successfully sent data \(String(data: data, encoding: .utf8) ?? "<nil>")")
    }

    /// Internal method to read SSE from the server
    private func readSSEEvents(
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        self.task = Task { [weak self] in
            guard let self else { return }

            do {
                let (asyncBytes, response) = try await self.urlSession.bytes(from: self.url)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode)
                else {
                    logger.error("Non-200 status code from SSE: \(response)")
                    throw TransportError.connectionFailed(
                        TransportError.invalidState("Non-200 status code from SSE: \(response)")
                    )
                }

                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard contentType.contains("text/event-stream") else {
                    throw TransportError.invalidState("Not an SSE response")
                }

                // we are connected now that we have a byte stream with no other response code errors
                logger.info("Connected to downchannel")
                await self.setState(.connected)

                // SSE lines typically come in the form of:
                // event: <something>
                // data: <something>
                // or
                // data: <json>
                // No whitespace rules are technically enforced, but we trim for whitespace on the endpoint event

                for try await line in asyncBytes.lines {
                    print("NOAH : \(line)")
                    let startingChars = line.prefix(6).lowercased()

                    if startingChars.starts(with: "event:") {
                        let event = String(line.dropFirst("event:".count))
                            .trimmingCharacters(in: .whitespaces)
                        await self.setCurrentEvent(event)
                        continue
                    }

                    if startingChars.starts(with: "data:") {
                        let rawData = String(line.dropFirst("data:".count))
                        logger.debug("Received SSE data: \(rawData)")
                        if await self.currentEvent == "endpoint" {
                            let trimmedEndpoint = rawData.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let newEndpoint = URL(string: trimmedEndpoint) {
                                await self.setPostEndpoint(newEndpoint)
                                continue
                            }
                        } else {
                            let trimmed = rawData.trimmingCharacters(in: .whitespaces)
                            if let data = trimmed.data(using: .utf8) {
                                logger.debug("Yielding SSE data: \(data)")
                                continuation.yield(data)
                                continue
                            }
                        }
                    }
                    // unhandled event / message payload
                    throw TransportError.invalidMessage("Unhandled line of byte stream in SSEClientTransport. Line must start 'data:' or 'event:' . Line was: \(line)")
                }
                logger.info("SSE downchannel closed")
                continuation.finish()
            } catch {
                logger.error("Error reading SSE events: \(error)")
                continuation.finish(throwing: error)
            }
        }
    }

    private func setCurrentEvent(_ event: String) {
        logger.debug("[setCurrentEvent] Setting current event to \(event)")
        self.currentEvent = event
    }

    private func setState(_ state: TransportState) {
        logger.debug("[setState] Setting current transport state to \(state)")
        self.state = state
    }

    private func setPostEndpoint(_ endpoint: URL) {
        logger.debug("[setPostEndpoint] setting postEndpoint URL \(endpoint)")
        self.postEndpoint = endpoint
    }

}
