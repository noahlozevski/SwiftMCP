import Foundation

/// A sample request/response pair for the "initialize" method as per the schema.
public struct InitializeRequest: MCPRequest {
    public static let method = "initialize"
    public typealias Response = InitializeResult

    public struct Params: Codable, Sendable {
        public let capabilities: ClientCapabilities
        public let clientInfo: Implementation
        public let protocolVersion: String
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
    public let _meta: [String: AnyCodable]?
}

public struct ClientCapabilities: Codable, Sendable {
    public let experimental: [String: [String: AnyCodable]]?
    public let roots: RootsCapability?
    public let sampling: [String: AnyCodable]?

    public struct RootsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }
}

public struct Implementation: Codable, Sendable {
    public let name: String
    public let version: String
}

public struct ServerCapabilities: Codable, Sendable {
    public let experimental: [String: [String: AnyCodable]]?
    public let logging: [String: AnyCodable]?
    public let prompts: PromptsCapability?
    public let resources: ResourcesCapability?
    public let tools: ToolsCapability?

    public struct PromptsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }

    public struct ResourcesCapability: Codable, Sendable {
        public let listChanged: Bool?
        public let subscribe: Bool?
    }

    public struct ToolsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }
}
