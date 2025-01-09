import Foundation
@preconcurrency import JSONSchema

public struct MCPTool: Codable, Sendable {
    /// The name of the tool.
    public let name: String

    /// The description of the tool.
    public var description: String?

    /// The input schema for the tool.
    public let inputSchema: Schema

    /// The connection ID associated with the tool.
    public var connectionId: String?

    public var id: String { name + (connectionId ?? "") }

    public init(
        name: String,
        description: String? = nil,
        inputSchema: Schema,
        connectionId: String? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.connectionId = connectionId
    }
}

extension MCPTool: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

public struct CallToolRequest: MCPRequest {
    public static let method = "tools/call"
    public typealias Response = CallToolResult

    public struct Params: MCPRequestParams {
        public var _meta: RequestMeta?
        public let name: String
        public let arguments: [String: AnyCodable]

        public init(name: String, arguments: [String: AnyCodable]?) {
            self.name = name
            self.arguments = arguments ?? [:]
        }
    }

    public var params: Params

    public init(name: String, arguments: [String: Any]? = nil) {
        self.params = Params(name: name, arguments: arguments?.mapValues(AnyCodable.init))
    }
}

public struct CallToolResult: MCPResponse {
    public typealias Request = CallToolRequest

    public let content: [ToolContent]
    public let isError: Bool?
    public var _meta: [String: AnyCodable]?
}

public enum ToolContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResourceContent)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(TextContent.self), text.type == "text" {
            self = .text(text)
        } else if let image = try? container.decode(ImageContent.self), image.type == "image" {
            self = .image(image)
        } else if let resource = try? container.decode(
            EmbeddedResourceContent.self
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

    public struct Params: MCPRequestParams {
        public var _meta: RequestMeta?
        public let cursor: String?
    }

    public var params: Params

    public init(cursor: String? = nil) {
        self.params = Params(cursor: cursor)
    }
}

public struct ListToolsResult: MCPResponse {
    public typealias Request = ListToolsRequest

    public var _meta: [String: AnyCodable]?
    public let tools: [MCPTool]
    public let nextCursor: String?
}
