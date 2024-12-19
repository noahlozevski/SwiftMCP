import Foundation

public struct ListPromptsRequest: MCPRequest {
    public static let method = "prompts/list"
    public typealias Response = ListPromptsResult

    public struct Params: Codable, Sendable {
        public let cursor: String?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(cursor: String? = nil) {
        self.internalParams = Params(cursor: cursor)
    }
}

public struct ListPromptsResult: MCPResponse {
    public typealias Request = ListPromptsRequest

    public let prompts: [Prompt]
    public let nextCursor: String?
    public let metadata: [String: AnyCodable]?

    public init(
        prompts: [Prompt],
        nextCursor: String? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.prompts = prompts
        self.nextCursor = nextCursor
        self.metadata = metadata
    }
}

public struct Prompt: Codable, Sendable {
    public let name: String
    public let description: String?
    public let arguments: [PromptArgument]?

    public init(
        name: String,
        description: String? = nil,
        arguments: [PromptArgument]? = nil
    ) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }
}

public struct PromptArgument: Codable, Sendable {
    public let name: String
    public let description: String?
    public let required: Bool?

    public init(
        name: String,
        description: String? = nil,
        required: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.required = required
    }
}

public struct PromptMessage: Codable, Sendable {
    public let role: Role
    public let content: PromptContent

    public enum PromptContent: Codable, Sendable {
        case text(TextContent)
        case image(ImageContent)
        case resource(EmbeddedResourceContent)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let textContent = try? container.decode(
                TextContent.self
            ), textContent.type == "text" {
                self = .text(textContent)
                return
            }
            if let imageContent = try? container.decode(
                ImageContent.self
            ), imageContent.type == "image" {
                self = .image(imageContent)
                return
            }
            if let resourceContent = try? container.decode(
                EmbeddedResourceContent.self
            ), resourceContent.type == "resource" {
                self = .resource(resourceContent)
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid PromptContent")
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let textContent): try textContent.encode(to: encoder)
            case .image(let imageContent): try imageContent.encode(to: encoder)
            case .resource(let resourceContent): try resourceContent.encode(to: encoder)
            }
        }
    }
}

public struct GetPromptRequest: MCPRequest {
    public static let method = "prompts/get"
    public typealias Response = GetPromptResult

    public struct Params: Codable, Sendable {
        public let name: String
        public let arguments: [String: String]?
    }

    public var params: Encodable? { internalParams }

    private let internalParams: Params

    public init(name: String, arguments: [String: String]? = nil) {
        self.internalParams = Params(name: name, arguments: arguments)
    }
}

public struct GetPromptResult: MCPResponse {
    public typealias Request = GetPromptRequest

    public let _meta: [String: AnyCodable]?
    public let description: String?
    public let messages: [PromptMessage]

    public struct PromptArgument: Codable {
        public let name: String
        public let description: String?
        public let required: Bool?
    }
}
