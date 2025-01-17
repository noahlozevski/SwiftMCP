import os // for logger
import Foundation

public actor SSEClientTransport: MCPTransport {

    public let configuration: TransportConfiguration

    private var _state: TransportState = .disconnected
    /// The current state of the transport
    public private(set) var state: TransportState {
        get {
            return _state
        }
        set {
            _state = newValue
            if let transportStateContinuation {
                transportStateContinuation.yield(newValue)
            }
        }
    }

    /// The endpoint we receive via the `endpoint` SSE event. Once known, we POST to it for sending messages.
    public private(set) var postEndpoint: URL?

    /// The base URL for the SSE connection (GET) request.
    private let sseURL: URL

    /// Used for parsing SSE events
    private var currentEvent: String?

    /// Our internal `EventSource` task
    private var task: Task<Void, Never>?

    /// The continuation for the messages stream
    private var messagesContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    /// The continuation for the transport state event stream
    private var transportStateContinuation: AsyncStream<TransportState>.Continuation?

    /// A unique session identifier
    private let sessionId: String

    /// Extra request configuration (like headers) if needed
    private let urlSession: URLSession

    private let logger: Logger

    public init(
        // ex: http://localhost:3000/sse
        // This is the exact url used to setup the down channel
        // The sending / POST url will be received during client capability discovery
        // For now, the origin of the SSE url MUST match the origin of the POST url
        sseURL: URL,
        configuration: TransportConfiguration = .default,
        urlSession: URLSession = .sseSession()
    ) {
        // TODO: assert URL is remote
        // TODO: assert we can identify the base URL
        self.sseURL = sseURL
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

    public func transportState() -> AsyncStream<TransportState> {
        AsyncStream { continuation in
            self.transportStateContinuation = continuation
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

        let sessionCookie = "browser%2Fnoahlozevski%2FqtkLZunfUWbKHSqIyFkIPvLAnD9gWQDM.pVjbxJwtdzU%2FkCi2oYZ0MVmM9JB43apvLHMbBvRn1%2B8"
        request.addValue("sessionId=\(sessionCookie)", forHTTPHeaderField: "Cookie")

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
                let (asyncBytes, response) = try await self.urlSession.bytes(for: {
                    var request = URLRequest(url: self.sseURL)
                    request.httpMethod = "GET"

                    // Add the hardcoded cookie to the header
                    let sessionCookie = "browser%2Fnoahlozevski%2FqtkLZunfUWbKHSqIyFkIPvLAnD9gWQDM.pVjbxJwtdzU%2FkCi2oYZ0MVmM9JB43apvLHMbBvRn1%2B8"
                    request.addValue("sessionId=\(sessionCookie)", forHTTPHeaderField: "Cookie")

                    return request
                }())

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
                    throw TransportError.invalidState("bad content type headers")
                }
                let cacheControl = httpResponse.value(forHTTPHeaderField: "Cache-Control") ?? ""
                guard cacheControl.contains("no-cache") else {
                    throw TransportError.invalidState("bad cache headers")
                }
//                let connection = httpResponse.value(forHTTPHeaderField: "Connection") ?? ""
//                guard connection.contains("keep-alive") else {
//                    throw TransportError.invalidState("bad connection header")
//                }

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
                            // ex: /message?sessionId=252e9336-68c5-49d1-be3d-8f7b2fa3b0df or http://localhost/message?sessionId=....
                            let endpointOrPath = rawData.trimmingCharacters(in: .whitespacesAndNewlines)
                            // if the path is a resource, then append to current endpoint origin
                            // Otherwise, parse as a URL and assert the origin matches the origin of self.url
                            if let newEndpoint = URL(string: endpointOrPath, relativeTo: self.sseURL) {
                                try await self.setPostEndpoint(newEndpoint)
                                continue
                            }
                        } else {
                            // we received "data: "
                            let trimmed = rawData.trimmingCharacters(in: .whitespaces)
                            if let data = trimmed.data(using: .utf8) {
                                logger.debug("Yielding SSE data: \(data)")
                                continuation.yield(data)
                                continue
                            }
                        }
                    }
                    // unhandled event / message payload
//                    throw TransportError.invalidMessage("Unhandled line of byte stream in SSEClientTransport. Line must start 'data:' or 'event:' . Line was: \(line)")
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

    /// Throws if the endpoint passed doesnt match the origin / scheme of the sseURL
    private func setPostEndpoint(_ endpoint: URL) throws {
        let ssePath = URL(string:"/", relativeTo: self.sseURL)
        let endpointPath = URL(string:"/", relativeTo: endpoint)
        if ssePath?.absoluteString != endpointPath?.absoluteString {
            // TODO: better error
            throw TransportError.invalidState("origin of SSE url \(ssePath?.absoluteString) and POST url \(endpointPath?.absoluteString) dont match")
        }
        logger.debug("[setPostEndpoint] setting postEndpoint URL \(endpoint)")
        self.postEndpoint = endpoint
    }

}


public extension URLSession {
    public static func sseSession() -> URLSession {
        let session = URLSession(configuration: .default)
        session.configuration.timeoutIntervalForRequest = .infinity
        session.configuration.timeoutIntervalForResource = .infinity
        session.configuration.waitsForConnectivity = true
        return session
    }
}
