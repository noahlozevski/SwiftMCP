import Foundation

public struct MCPContext {
    public let id: String
    public let serverInfo: Implementation
    public let capabilities: ServerCapabilities
    public let resources: [MCPResource]
    public let prompts: [MCPPrompt]
    public let tools: [MCPTool]
    public let instructions: String?
}

public protocol MCPHostConfiguration {
    /// The default client configuration to use when creating new clients
    var defaultClientConfig: MCPClient.Configuration { get }
}

public protocol MCPContextManaging {
    func handleSampling(_ request: CreateMessageRequest, from client: MCPClient) async throws
        -> CreateMessageResult
}

/// Host should:
/// - Manage "sessions" between clients and servers
/// - Aggregate tools, prompts, resources from sessions
/// - Aggregate notifications from sessions
/// - Hand off sampling requests to the consumer
/// - Enable / Disable Connections
/// - register for notifications
///
///

public actor MCPHost {
    private let configuration: MCPHostConfiguration
    private var contextManager: MCPContextManaging?

    private struct ServerConnection: Identifiable, Sendable {
        let id: String
        let serverInfo: Implementation
        let capabilities: ServerCapabilities

        let transport: any MCPTransport
        let client: MCPClient

        /// Aggregated capabilities from the server

        var resources: [MCPResource] = []
        var prompts: [MCPPrompt] = []
        var tools: [MCPTool] = []

        /// Initialization instructions, if present, for the host to combine or store.
        var instructions: String?
    }

    private var connections: [String: ServerConnection] = [:]

    public init(configuration: MCPHostConfiguration) {
        self.configuration = configuration
    }

    public func registerContextManager(_ manager: MCPContextManaging) {
        contextManager = manager
    }

    public func connect(
        _ id: String,
        transport: MCPTransport
    ) async throws {
        let clientConfig = configuration.defaultClientConfig
        let client = MCPClient(
            clientInfo: clientConfig.clientInfo, capabilities: clientConfig.capabilities)

        try await client.start(transport)

        guard case .running(let sessionInfo) = await client.state else {
            throw MCPError.internalError("Expected running state")
        }

        async let prompts = try await client.listPrompts()
        async let tools = try await client.listTools()
        async let resources = try await client.listResources()

        let serverInfo = ServerConnection(
            id: id,
            serverInfo: sessionInfo.serverInfo,
            capabilities: sessionInfo.capabilities,
            transport: transport,
            client: client,
            resources: try await resources.resources,
            prompts: try await prompts.prompts,
            tools: try await tools.tools,
            instructions: sessionInfo.instructions
        )

        connections[id] = serverInfo
    }

    public func disconnect(_ id: String) async {
        guard let connection = connections.removeValue(forKey: id) else {
            return
        }

        await connection.client.stop()
    }

    public func getContext(for id: String) async throws -> MCPContext {
        guard let connection = connections[id] else {
            throw MCPError.invalidRequest("No connection found for \(id)")
        }

        return MCPContext(
            id: id,
            serverInfo: connection.serverInfo,
            capabilities: connection.capabilities,
            resources: connection.resources,
            prompts: connection.prompts,
            tools: connection.tools,
            instructions: connection.instructions
        )
    }
}
