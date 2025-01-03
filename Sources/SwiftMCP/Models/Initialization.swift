import Foundation

/// A sample request/response pair for the "initialize" method as per the schema.
public struct InitializeRequest: MCPRequest {
    public var params: Params

    public static let method = "initialize"
    public typealias Response = InitializeResult

    public struct Params: MCPRequestParams {
        public var _meta: RequestMeta?
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

    public init(params: Params) {
        self.params = params
    }
}

public struct InitializeResult: MCPResponse, Equatable {
    public typealias Request = InitializeRequest
    public let capabilities: ServerCapabilities
    public let protocolVersion: String
    public let serverInfo: Implementation
    public let instructions: String?
    public var _meta: [String: AnyCodable]?

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
        self._meta = meta
    }

    public static func == (lhs: InitializeResult, rhs: InitializeResult) -> Bool {
        return (lhs.capabilities == rhs.capabilities)
            && (lhs.protocolVersion == rhs.protocolVersion)
            && (lhs.serverInfo == rhs.serverInfo) && (lhs.instructions == rhs.instructions)
    }
}

public struct ClientCapabilities: Codable, Sendable {
    public var experimental: [String: [String: AnyCodable]]?
    public var roots: RootsCapability?
    public var sampling: [String: AnyCodable]?

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
        return (lhs.roots == rhs.roots) && (lhs.experimental == rhs.experimental)
            && (lhs.sampling == rhs.sampling)
    }
}

extension ClientCapabilities: CustomStringConvertible {
    public var description: String {
        var desc = "ClientCapabilities("
        if let roots = roots {
            desc += "\nroots: \(roots),"
        }
        if let sampling = sampling {
            desc += "\nsampling: \(sampling),"
        }

        return desc + ")"
    }
}

extension ClientCapabilities {
    public struct Features: OptionSet {
        public let rawValue: Int

        public static let roots = Features(rawValue: 1 << 0)
        public static let sampling = Features(rawValue: 1 << 1)
        public static let experimental = Features(rawValue: 1 << 2)

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public var supportedFeatures: Features {
        var features = Features()
        if roots != nil { features.insert(.roots) }
        if sampling != nil { features.insert(.sampling) }
        if experimental != nil { features.insert(.experimental) }
        return features
    }

    public func supports(_ feature: Features) -> Bool {
        return supportedFeatures.contains(feature)
    }
}

public struct Implementation: Codable, Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public static let defaultClient = Implementation(
        name: Bundle.main.bundleIdentifier ?? "SwiftMCP",
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    )
}

public struct ServerCapabilities: Codable, Sendable {
    public var experimental: [String: [String: AnyCodable]]?
    public var logging: [String: AnyCodable]?
    public var prompts: PromptsCapability?
    public var resources: ResourcesCapability?
    public var tools: ToolsCapability?

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

extension ServerCapabilities: CustomStringConvertible {
    public var description: String {
        var desc = "ServerCapabilities("
        if let prompts = prompts {
            desc += "prompts: \(prompts), "
        }
        if let resources = resources {
            desc += "resources: \(resources), "
        }
        if let tools = tools {
            desc += "tools: \(tools), "
        }
        desc += ")"
        return desc
    }
}

extension ServerCapabilities: Equatable {
    public static func == (lhs: ServerCapabilities, rhs: ServerCapabilities) -> Bool {
        return (lhs.prompts == rhs.prompts) && (lhs.resources == rhs.resources)
            && (lhs.tools == rhs.tools) && (lhs.experimental == rhs.experimental)
            && (lhs.logging == rhs.logging)
    }
}

extension ServerCapabilities {
    public struct Features: OptionSet {
        public let rawValue: Int

        public static let tools = Features(rawValue: 1 << 0)
        public static let resources = Features(rawValue: 1 << 1)
        public static let resourceListChanged = Features(rawValue: 1 << 2)
        public static let resourceSubscribe = Features(rawValue: 1 << 3)
        public static let prompts = Features(rawValue: 1 << 4)
        public static let promptListChanged = Features(rawValue: 1 << 5)

        public static let logging = Features(rawValue: 1 << 6)

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public var supportedFeatures: Features {
        var features = Features()
        if tools != nil { features.insert(.tools) }
        if let resources {
            features.insert(.resources)

            if resources.listChanged != nil {
                features.insert(.resourceListChanged)
            }

            if resources.subscribe != nil {
                features.insert(.resourceSubscribe)
            }
        }
        if let prompts {
            features.insert(.prompts)

            if prompts.listChanged != nil {
                features.insert(.promptListChanged)
            }
        }
        return features
    }

    public func supports(_ feature: Features) -> Bool {
        return supportedFeatures.contains(feature)
    }
}
