import Foundation

public struct MCPTool: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: ToolInputSchema

    public struct ToolInputSchema: Codable, Sendable {
        public let type: String
        public let properties: [String: SchemaProperty]?
        public let required: [String]?

        public struct SchemaProperty: Codable, Sendable {
            // We allow any schema object, but minimal:
            public let type: String?
            public let description: String?
            public let additionalProperties: [String: AnyCodable]?
        }
    }
}

public struct CallToolRequest: MCPRequest {
    public static let method = "tools/call"
    public typealias Response = CallToolResult

    public struct Params: Codable, Sendable {
        public let name: String
        public let arguments: [String: AnyCodable]

        public init(name: String, arguments: [String: AnyCodable]?) {
            self.name = name
            self.arguments = arguments ?? [:]
        }
    }
    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(name: String, arguments: [String: AnyCodable]? = nil) {
        self.internalParams = Params(name: name, arguments: arguments)
    }
}

public struct CallToolResult: MCPResponse {
    public typealias Request = CallToolRequest

    public let content: [ToolContent]
    public let isError: Bool?
    public let meta: [String: AnyCodable]?
}

public enum ToolContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResource)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(TextContent.self), text.type == "text" {
            self = .text(text)
        } else if let image = try? container.decode(ImageContent.self), image.type == "image" {
            self = .image(image)
        } else if let resource = try? container.decode(
            EmbeddedResource.self
        ), resource.type == "resource" {
            self = .resource(resource)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown tool content type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text): try text.encode(to: encoder)
        case .image(let image): try image.encode(to: encoder)
        case .resource(let resource): try resource.encode(to: encoder)
        }
    }
}

public struct ListToolsRequest: MCPRequest {
    public static let method = "tools/list"
    public typealias Response = ListToolsResult

    public struct Params: Codable, Sendable {
        public let cursor: String?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(cursor: String? = nil) {
        self.internalParams = Params(cursor: cursor)
    }
}

public struct ListToolsResult: MCPResponse {
    public typealias Request = ListToolsRequest

    public let _meta: [String: AnyCodable]?
    public let tools: [MCPTool]
    public let nextCursor: String?
}
