import Foundation

/// A sample request/response pair for the "initialize" method as per the schema.
public struct InitializeRequest: MCPRequest {
    public static let method = "initialize"
    public typealias Response = InitializeResult

    public struct Params: Codable, Sendable {
        public let capabilities: ClientCapabilities
        public let clientInfo: Implementation
        public let protocolVersion: String

        public init(
            capabilities: ClientCapabilities, clientInfo: Implementation, protocolVersion: String
        ) {
            self.capabilities = capabilities
            self.clientInfo = clientInfo
            self.protocolVersion = protocolVersion
        }
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(params: Params) {
        self.internalParams = params
    }
}

public struct InitializeResult: MCPResponse {
    public typealias Request = InitializeRequest
    public let capabilities: ServerCapabilities
    public let protocolVersion: String
    public let serverInfo: Implementation
    public let instructions: String?
    public let meta: [String: AnyCodable]?

    public init(
        capabilities: ServerCapabilities,
        protocolVersion: String,
        serverInfo: Implementation,
        instructions: String? = nil,
        meta: [String: AnyCodable]? = nil
    ) {
        self.capabilities = capabilities
        self.protocolVersion = protocolVersion
        self.serverInfo = serverInfo
        self.instructions = instructions
        self.meta = meta
    }
}

public struct ClientCapabilities: Codable, Sendable {
    public let experimental: [String: [String: AnyCodable]]?
    public let roots: RootsCapability?
    public let sampling: [String: AnyCodable]?

    public struct RootsCapability: Codable, Sendable, Equatable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public init(
        experimental: [String: [String: AnyCodable]]? = nil,
        roots: RootsCapability? = nil,
        sampling: [String: AnyCodable]? = nil
    ) {
        self.experimental = experimental
        self.roots = roots
        self.sampling = sampling
    }
}

extension ClientCapabilities: Equatable {
    public static func == (lhs: ClientCapabilities, rhs: ClientCapabilities) -> Bool {
        // TODO: Full comparison
        return lhs.roots == rhs.roots
    }
}

public struct Implementation: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct ServerCapabilities: Codable, Sendable {
    public let experimental: [String: [String: AnyCodable]]?
    public let logging: [String: AnyCodable]?
    public let prompts: PromptsCapability?
    public let resources: ResourcesCapability?
    public let tools: ToolsCapability?

    public struct PromptsCapability: Codable, Sendable, Equatable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public struct ResourcesCapability: Codable, Sendable, Equatable {
        public let listChanged: Bool?
        public let subscribe: Bool?

        public init(listChanged: Bool? = nil, subscribe: Bool? = nil) {
            self.listChanged = listChanged
            self.subscribe = subscribe
        }
    }

    public struct ToolsCapability: Codable, Sendable, Equatable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public init(
        experimental: [String: [String: AnyCodable]]? = nil,
        logging: [String: AnyCodable]? = nil,
        prompts: PromptsCapability? = nil,
        resources: ResourcesCapability? = nil,
        tools: ToolsCapability? = nil
    ) {
        self.experimental = experimental
        self.logging = logging
        self.prompts = prompts
        self.resources = resources
        self.tools = tools
    }
}

extension ServerCapabilities: Equatable {
    public static func == (lhs: ServerCapabilities, rhs: ServerCapabilities) -> Bool {
        // TODO: Full comparison
        return (lhs.prompts == rhs.prompts) && (lhs.resources == rhs.resources)
            && (lhs.tools == rhs.tools)
    }
}

